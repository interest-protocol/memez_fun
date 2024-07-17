module memez_fun::memez_fun {
    // === Imports ===

    use std::type_name::{Self, TypeName};

    use sui::{
        sui::SUI,
        dynamic_field as df,
        table::{Self, Table},
        vec_map::{Self, VecMap},     
        vec_set::{Self, VecSet},
        balance::{Self, Balance},   
        coin::{Coin, TreasuryCap, CoinMetadata},
    };

    use suitears::math64::{mul_div_up, min};
    
    use memez_v2_invariant::memez_v2_invariant::{invariant_, get_amount_out};

    use memez_fun::{
        memez_fun_utils as utils,
        memez_fun_errors as errors,
        memez_fun_events as events,
    };

    // === Constants ===
    
    const FIVE_SUI: u64 = 5_000_000_000;
    
    // 0.3%
    const INITIAL_SWAP_FEE: u64 = 3_000_000;

    //@dev 1e9 === 100%
    const PRECISION: u64 = 1_000_000_000;
    // 2%
    const MAX_SWAP_FEE: u64 = 20_000_000;
    // 50%
    const MAX_BURN_PERCENT: u64 = 500_000_000;
    const DEAD_WALLET: address = @0x0;
    const MEME_TOTAL_SUPPLY: u64 = 1_000_000_000_000_000_000;
    const MEME_DECIMALS: u8 = 9;

    // === Structs ===

    public struct Admin has key, store {
        id: UID
    }

    public struct PoolKey<phantom CoinX, phantom CoinY> has drop {}

    public struct StateKey has copy, drop, store {}

    public struct Config has key {
        id: UID,
        /// type_name::get<PoolKey>() => Pool address
        pools: Table<TypeName, address>,
        admin: address,
        create_fee: u64,
        swap_fee: u64,
        initial_virtual_liquidity_config: VecMap<TypeName, u64>,
        migration_liquidity_config: VecMap<TypeName, u64>,
        whitelist: VecSet<TypeName>,
    }

    public struct FunPoolState<phantom CoinX, phantom CoinY> has store {
        balance_x: Balance<CoinX>,
        balance_y: Balance<CoinY>,
        admin_balance_x: Balance<CoinX>,
        admin_balance_y: Balance<CoinY>,
        swap_fee: u64,
        liquidity_x: u64,
        liquidity_y: u64,
        is_migrating: bool,
        is_x_virtual: bool,
        burn_percent: u64,
        migration_liquidity_target: u64,
        migration_witness: TypeName,
        admin: address
    }

    public struct FunPool has key {
        id: UID,
    }

    // === Public-Mutative Functions ===

    fun init(ctx: &mut TxContext) {
        transfer::public_transfer(Admin { id: object::new(ctx) }, ctx.sender());
        transfer::share_object(
            Config {
                id: object::new(ctx),
                pools: table::new(ctx),
                create_fee: FIVE_SUI,
                swap_fee: INITIAL_SWAP_FEE,
                initial_virtual_liquidity_config: vec_map::empty(),
                migration_liquidity_config: vec_map::empty(),
                whitelist: vec_set::empty(),
                admin: @admin
            }
        );
    }

    public fun new<CoinA, CoinB, Witness: drop>(
        config: &mut Config,
        mut treasury_cap: TreasuryCap<CoinA>,
        metadata: &CoinMetadata<CoinA>,
        create_fee: Coin<SUI>,
        burn_percent: u64,
        ctx: &mut TxContext
    ): FunPool {
        assert!(config.whitelist.contains(&type_name::get<Witness>()), errors::witness_not_whitelisted_to_migrate());
        assert!(treasury_cap.total_supply() == 0, errors::must_have_no_supply());
        assert!(metadata.get_decimals() == MEME_DECIMALS, errors::must_have_nine_decimals());
        assert!(create_fee.value() >= config.create_fee, errors::create_fee_is_too_low());
        assert!(
            config.initial_virtual_liquidity_config.contains(&type_name::get<CoinB>()) 
            && config.migration_liquidity_config.contains(&type_name::get<CoinB>()),
            errors::no_config_available()
        );
        assert!(MAX_BURN_PERCENT >= burn_percent, errors::burn_percent_is_too_high());

        let balance_a = treasury_cap.mint(MEME_TOTAL_SUPPLY, ctx).into_balance();
        let balance_b = balance::zero<CoinB>();

        transfer::public_transfer(treasury_cap, DEAD_WALLET);
        transfer::public_transfer(create_fee, config.admin);

        if (utils::are_coins_ordered<CoinA, CoinB>())
            config.new_impl<CoinA, CoinB, Witness>(balance_a, balance_b,  false, burn_percent, ctx)
        else 
            config.new_impl<CoinB, CoinA, Witness>(balance_b, balance_a,  true, burn_percent, ctx)
    }

    public fun swap<CoinIn, CoinOut>(
        pool: &mut FunPool, 
        coin_in: Coin<CoinIn>,
        coin_min_value: u64,
        ctx: &mut TxContext    
    ): Coin<CoinOut> {
        assert!(coin_in.value() != 0, errors::no_zero_value());

        if (utils::is_coin_x<CoinIn, CoinOut>()) 
            pool.swap_coin_x<CoinIn, CoinOut>(coin_in, coin_min_value, ctx)
        else 
            pool.swap_coin_y<CoinOut, CoinIn>(coin_in, coin_min_value, ctx)
    }

    #[allow(lint(share_owned))]
    public fun share(self: FunPool) {
        transfer::share_object(self);
    }

    public fun migrate<CoinX, CoinY, Witness: drop>(
        mut pool: FunPool, 
        _: Witness, 
        ctx: &mut TxContext
    ): (Coin<CoinX>, Coin<CoinY>) {
        
        let state = df::remove<StateKey, FunPoolState<CoinX, CoinY>>(&mut pool.id, StateKey {});

        let FunPoolState {
            balance_x,
            balance_y,
            admin_balance_x,
            admin_balance_y,
            swap_fee: _,
            liquidity_x: _,
            liquidity_y: _,
            is_migrating,
            is_x_virtual,
            migration_liquidity_target: _,
            admin,
            migration_witness,
            burn_percent
        } = state;

        assert!(migration_witness == type_name::get<Witness>(), errors::incorrect_migration_witness());
        assert!(is_migrating, errors::must_be_migrating());

        let mut coin_x = balance_x.into_coin(ctx);
        let mut coin_y = balance_y.into_coin(ctx);

        if (is_x_virtual) {
            let burn_value = mul_div_up(coin_y.value(), burn_percent, PRECISION);
            transfer::public_transfer(coin_y.split(burn_value, ctx), DEAD_WALLET)
        } else {
            let burn_value = mul_div_up(coin_x.value(), burn_percent, PRECISION);
            transfer::public_transfer(coin_x.split(burn_value, ctx), DEAD_WALLET);
        }; 

        let FunPool { id } = pool;

        events::migrated(
            id.to_address(), 
            type_name::get<CoinX>(),
            type_name::get<CoinY>(),
            coin_x.value(),
            coin_y.value(),
            admin_balance_x.value(),
            admin_balance_y.value(),
            migration_witness
        );

        transfer::public_transfer(admin_balance_x.into_coin(ctx), admin);
        transfer::public_transfer(admin_balance_y.into_coin(ctx), admin);

        id.delete();

        (
            coin_x,
            coin_y
        )
    }

    // === Public-View Functions ===

    public fun pools(config: &Config): &Table<TypeName, address> {
        &config.pools
    }

    public use fun registry_admin as Config.admin;
    public fun registry_admin(config: &Config): address {
        config.admin
    }

    public fun pool_address<CoinA, CoinB>(config: &Config): Option<address> {
        let key = make_pool_key<CoinA, CoinB>();
        if (config.pools.contains(key))
            option::some(*config.pools.borrow(key))
        else
            option::none()
    }

    public fun create_fee(config: &Config): u64 {
        config.create_fee
    }

    public fun swap_fee(config: &Config): u64 {
        config.swap_fee
    }

    public fun initial_virtual_liquidity_config(config: &Config): VecMap<TypeName, u64> {
        config.initial_virtual_liquidity_config
    }

    public fun migration_liquidity_config(config: &Config): VecMap<TypeName, u64> {
        config.migration_liquidity_config
    }

    public fun exists_<CoinA, CoinB>(config: &Config): bool {
        config.pools.contains(make_pool_key<CoinA, CoinB>())   
    }

    public fun balance_x<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.balance_x.value()
    }

    public fun balance_y<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.balance_y.value()
    }

    public fun admin_balance_x<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.admin_balance_x.value()
    }

    public fun admin_balance_y<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.admin_balance_y.value()
    }

    public use fun pool_swap_fee as FunPool.swap_fee;
    public fun pool_swap_fee<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.swap_fee
    }

    public fun liquidity_x<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.liquidity_x
    }

    public fun liquidity_y<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.liquidity_y
    }

    public fun is_migrating<CoinX, CoinY>(pool: &FunPool): bool {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.is_migrating
    }

    public fun is_x_virtual<CoinX, CoinY>(pool: &FunPool): bool {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.is_x_virtual
    }

    public fun burn_percent<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.burn_percent
    }

    public fun migration_liquidity_target<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.migration_liquidity_target
    }

    public fun migration_witness<CoinX, CoinY>(pool: &FunPool): TypeName {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.migration_witness
    }

    public use fun pool_admin as FunPool.admin;
    public fun pool_admin<CoinX, CoinY>(pool: &FunPool): address {
        let pool_state = pool.state<CoinX, CoinY>();
        pool_state.admin
    }

    // === Admin Functions ===

    public fun take_fees<CoinX, CoinY>(pool: &mut FunPool, _: &Admin, ctx: &mut TxContext): (Coin<CoinX>, Coin<CoinY>) {
        let pool_state = pool.state_mut<CoinX, CoinY>();

        (
            pool_state.admin_balance_x.withdraw_all().into_coin(ctx),
            pool_state.admin_balance_y.withdraw_all().into_coin(ctx),
        )
    }

    public fun update_admin(config: &mut Config, _: &Admin, admin: address) {
        config.admin = admin;
    }

    public fun update_create_fee(config: &mut Config, _: &Admin, fee: u64) {
        config.create_fee = fee;
    }

    public fun update_swap_fee(config: &mut Config, _: &Admin, fee: u64) {
        assert!(MAX_SWAP_FEE >= fee, errors::swap_fee_is_too_high());
        config.create_fee = fee;
    }

    public fun update_initial_virtual_liquidity<CoinType>(config: &mut Config, _: &Admin, liquidity: u64) {
        safe_map_insert<CoinType>(&mut config.initial_virtual_liquidity_config);
        
        let v = config.initial_virtual_liquidity_config.get_mut(&type_name::get<CoinType>());

        *v = liquidity;
    }

    public fun update_migration_liquidity<CoinType>(config: &mut Config, _: &Admin, liquidity: u64) {
        safe_map_insert<CoinType>(&mut config.migration_liquidity_config);
        
        let v = config.migration_liquidity_config.get_mut(&type_name::get<CoinType>());

        *v = liquidity;
    }

    public fun add_migrator<Witness>(config: &mut Config, _: &Admin) {
        config.whitelist.insert(type_name::get<Witness>());
    }

    public fun remove_migrator<Witness>(config: &mut Config, _: &Admin) {
        config.whitelist.remove(&type_name::get<Witness>());
    }

    // === Private Functions ===

    fun new_impl<CoinX, CoinY, Witness>(
        config: &mut Config,
        balance_x: Balance<CoinX>,
        balance_y: Balance<CoinY>,
        is_x_virtual: bool,
        burn_percent: u64,
        ctx: &mut TxContext
    ): FunPool {
        let balance_x_value = balance_x.value();
        let balance_y_value = balance_y.value();

        let virtual_asset_key = if (is_x_virtual) type_name::get<CoinX>() else type_name::get<CoinY>();

        let virtual_liquidity = *config.initial_virtual_liquidity_config.get(&virtual_asset_key);
        let migration_liquidity_target = *config.migration_liquidity_config.get(&virtual_asset_key);

        let state = FunPoolState {
            balance_x,
            balance_y,
            admin_balance_x: balance::zero<CoinX>(),
            admin_balance_y: balance::zero<CoinY>(),
            liquidity_x: balance_x_value + if (is_x_virtual) virtual_liquidity else 0,
            liquidity_y: balance_y_value + if (is_x_virtual) 0 else virtual_liquidity,
            swap_fee: config.swap_fee,
            is_migrating: false,
            is_x_virtual,
            migration_liquidity_target,
            admin: config.admin,
            burn_percent,
            migration_witness: type_name::get<Witness>() 
        };

        let mut pool = FunPool {
            id: object::new(ctx)
        };

        events::new_fun_pool(
            pool.id.to_address(), 
            type_name::get<CoinX>(),
            type_name::get<CoinY>(),
            balance_x_value,
            balance_y_value,
            state.liquidity_x,
            state.liquidity_y,
            is_x_virtual,
            type_name::get<Witness>()
        );

        df::add(&mut pool.id, StateKey {}, state);

        config.pools.add(type_name::get<PoolKey<CoinX, CoinY>>(), pool.id.to_address());

        pool
    }

    fun swap_coin_x<CoinX, CoinY>(
        pool: &mut FunPool,
        mut coin_x: Coin<CoinX>,
        coin_y_min_value: u64,
        ctx: &mut TxContext
    ): Coin<CoinY> {
        let pool_address = pool.id.to_address();
        let pool_state = pool.state_mut<CoinX, CoinY>();
        assert!(!pool_state.is_migrating, errors::pool_is_migrating());

        let coin_in_amount = coin_x.value();
    
        let (amount_out, fee) = pool_state.swap_impl(
            coin_in_amount, 
            true,
        );

        if (fee != 0) {
            pool_state.admin_balance_x.join(coin_x.split(fee, ctx).into_balance());  
        };

        let value_x = coin_x.value();

        pool_state.balance_x.join(coin_x.into_balance());

        let out_value = min(amount_out, pool_state.balance_y.value());

        assert!(out_value >= coin_y_min_value, errors::slippage());

        pool_state.liquidity_x = pool_state.liquidity_x + value_x;
        pool_state.liquidity_y = pool_state.liquidity_y - out_value;

        events::swap(
            pool_address, 
            type_name::get<CoinX>(), 
            type_name::get<CoinY>(), 
            coin_in_amount, 
            amount_out, 
            fee
        );

        pool_state.may_be_toggle_migrate(pool_address);

        pool_state.balance_y.split(out_value).into_coin(ctx) 
    }

    fun swap_coin_y<CoinX, CoinY>(
        pool: &mut FunPool,
        mut coin_y: Coin<CoinY>,
        coin_x_min_value: u64,
        ctx: &mut TxContext
    ): Coin<CoinX> {
        let pool_address = pool.id.to_address();
        let pool_state = pool.state_mut<CoinX, CoinY>();
        assert!(!pool_state.is_migrating, errors::pool_is_migrating());

        let coin_in_amount = coin_y.value();
        
        let (amount_out, fee) = pool_state.swap_impl( 
            coin_in_amount, 
            false
        );

        if (fee != 0) {
            pool_state.admin_balance_y.join(coin_y.split(fee, ctx).into_balance());  
        };

        let value_y = coin_y.value();

        pool_state.balance_y.join(coin_y.into_balance());

        let out_value = min(amount_out, pool_state.balance_x.value());

        assert!(out_value >= coin_x_min_value, errors::slippage());

        pool_state.liquidity_x = pool_state.liquidity_x - out_value;
        pool_state.liquidity_y = pool_state.liquidity_y + value_y;

        events::swap(
            pool_address, 
            type_name::get<CoinY>(), 
            type_name::get<CoinX>(), 
            coin_in_amount, 
            amount_out, 
            fee
        );

        pool_state.may_be_toggle_migrate(pool_address);

        pool_state.balance_x.split(out_value).into_coin(ctx) 
    }  

    fun swap_impl<CoinX, CoinY>(
        pool_state: &FunPoolState<CoinX, CoinY>,
        coin_in_amount: u64,
        is_x: bool
    ): (u64, u64) {
        let (balance_x, balance_y) = (
            pool_state.liquidity_x,
            pool_state.liquidity_y
        );

        let prev_k = invariant_(balance_x, balance_y);

        let fee = mul_div_up(coin_in_amount, pool_state.swap_fee, PRECISION);

        let coin_in_amount = coin_in_amount - fee;

        let amount_out =  if (is_x) 
                get_amount_out(coin_in_amount, balance_x, balance_y)
            else 
                get_amount_out(coin_in_amount, balance_y, balance_x);

        let new_k = if (is_x)
                invariant_(balance_x + coin_in_amount, balance_y - amount_out)
            else
                invariant_(balance_x - amount_out, balance_y + coin_in_amount);

        // @dev impossible to trigger - sanity check
        assert!(new_k >= prev_k, errors::invalid_invariant());

        (amount_out, fee) 
    }

    fun may_be_toggle_migrate<CoinX, CoinY>(state: &mut FunPoolState<CoinX, CoinY>, pool: address) {
        let liquidity = if (state.is_x_virtual) state.liquidity_x else state.liquidity_y;

        if (liquidity >= state.migration_liquidity_target) {
            state.is_migrating = true;

            events::ready_for_migration(
                pool, 
                type_name::get<CoinX>(), 
                type_name::get<CoinY>(), 
                state.migration_witness
            );
        };
    }

    fun safe_map_insert<CoinType>(map: &mut VecMap<TypeName, u64>) {
        if (!map.contains(&type_name::get<CoinType>()))
            map.insert(type_name::get<CoinType>(), 0);
    }

    fun make_pool_key<CoinA, CoinB>(): TypeName {
        if (utils::is_coin_x<CoinA, CoinB>())
            type_name::get<PoolKey<CoinA, CoinB>>() 
        else 
            type_name::get<PoolKey<CoinB, CoinA>>()
    }

    fun state<CoinX, CoinY>(pool: &FunPool): &FunPoolState<CoinX, CoinY> {
        df::borrow(&pool.id, StateKey {})
    }

    fun state_mut<CoinX, CoinY>(pool: &mut FunPool): &mut FunPoolState<CoinX, CoinY> {
        df::borrow_mut(&mut pool.id,StateKey {})
    }

    // === Test Functions ===

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
