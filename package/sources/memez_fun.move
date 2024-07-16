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

    use suitears::math64::mul_div_up;
    
    use memez_v2_invariant::memez_v2_invariant::{invariant_, get_amount_out};

    use memez_fun::{
        memez_fun_utils as utils,
        memez_fun_errors as errors,
    };

    // === Errors ===

    // === Constants ===
    
    const FIVE_SUI: u64 = 5_000_000_000;
    
    // 0.3%
    const INITIAL_SWAP_FEE: u64 = 3000000;

    //@dev 1e9 === 100%
    const FEE_PRECISION: u64 = 1_000_000_000;

    const DEAD_WALLET: address = @0x0;
    const MEME_TOTAL_SUPPLY: u64 = 1_000_000_000_000_000_000;
    const MEME_DECIMALS: u8 = 9;

    // === Structs ===

    public struct Admin has key, store {
        id: UID
    }

    public struct PoolKey<phantom CoinX, phantom CoinY> has drop {}

    public struct StateKey has copy, drop, store {}

    public struct Registry has key {
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
        migration_liquidity_target: u64,
        migration_witness: TypeName,
        admin: address
    }

    public struct FunPool has key {
        id: UID,
    }

    public struct SwapAmount has store, drop, copy {
        amount_out: u64,
        fee: u64
    }

    // === Public-Mutative Functions ===

    fun init(ctx: &mut TxContext) {
        transfer::public_transfer(Admin { id: object::new(ctx) }, ctx.sender());
        transfer::share_object(
            Registry {
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
        registry: &mut Registry,
        mut treasury_cap: TreasuryCap<CoinA>,
        metadata: &CoinMetadata<CoinA>,
        create_fee: Coin<SUI>,
        ctx: &mut TxContext
    ): FunPool {
        assert!(registry.whitelist.contains(&type_name::get<Witness>()), errors::witness_not_whitelisted_to_migrate());
        assert!(treasury_cap.total_supply() == 0, errors::must_have_no_supply());
        assert!(metadata.get_decimals() == MEME_DECIMALS, errors::must_have_nine_decimals());
        assert!(create_fee.value() >= registry.create_fee, errors::create_fee_is_too_low());
        assert!(
            registry.initial_virtual_liquidity_config.contains(&type_name::get<CoinB>()) 
            && registry.migration_liquidity_config.contains(&type_name::get<CoinB>()),
            errors::no_config_available()
        );

        let balance_a = treasury_cap.mint(MEME_TOTAL_SUPPLY, ctx).into_balance();
        transfer::public_transfer(treasury_cap, DEAD_WALLET);
        let balance_b = balance::zero<CoinB>();
        transfer::public_transfer(create_fee, registry.admin);


        if (utils::are_coins_ordered<CoinA, CoinB>())
            new_impl<CoinA, CoinB, Witness>(registry, balance_a, balance_b,  false, ctx)
        else 
            new_impl<CoinB, CoinA, Witness>(registry, balance_b, balance_a,  true, ctx)
    }

    public fun swap<CoinIn, CoinOut>(
        pool: &mut FunPool, 
        coin_in: Coin<CoinIn>,
        coin_min_value: u64,
        ctx: &mut TxContext    
    ): Coin<CoinOut> {
        assert!(coin_in.value() != 0, errors::no_zero_value());

        if (utils::is_coin_x<CoinIn, CoinOut>()) 
            swap_coin_x<CoinIn, CoinOut>(pool, coin_in, coin_min_value, ctx)
        else 
            swap_coin_y<CoinOut, CoinIn>(pool, coin_in, coin_min_value, ctx)
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
            is_x_virtual: _,
            migration_liquidity_target: _,
            admin,
            migration_witness
        } = state;

        assert!(migration_witness == type_name::get<Witness>(), errors::incorrect_migration_witness());
        assert!(is_migrating, errors::must_be_migrating());

        transfer::public_transfer(admin_balance_x.into_coin(ctx), admin);
        transfer::public_transfer(admin_balance_y.into_coin(ctx), admin);

        let FunPool { id } = pool;
        id.delete();

        (
            balance_x.into_coin(ctx),
            balance_y.into_coin(ctx)
        )
    }

    // === Public-View Functions ===

    public fun pools(registry: &Registry): &Table<TypeName, address> {
        &registry.pools
    }

    public use fun registry_admin as Registry.admin;
    public fun registry_admin(registry: &Registry): address {
        registry.admin
    }

    public fun pool_address<CoinA, CoinB>(registry: &Registry): Option<address> {
        let key = make_pool_key<CoinA, CoinB>();
        if (registry.pools.contains(key))
            option::some(*registry.pools.borrow(key))
        else
            option::none()
    }

    public fun create_fee(registry: &Registry): u64 {
        registry.create_fee
    }

    public fun swap_fee(registry: &Registry): u64 {
        registry.swap_fee
    }

    public fun initial_virtual_liquidity_config(registry: &Registry): VecMap<TypeName, u64> {
        registry.initial_virtual_liquidity_config
    }

    public fun migration_liquidity_config(registry: &Registry): VecMap<TypeName, u64> {
        registry.migration_liquidity_config
    }

    public fun exists_<CoinA, CoinB>(registry: &Registry): bool {
        registry.pools.contains(make_pool_key<CoinA, CoinB>())   
    }

    public fun balance_x<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool_state<CoinX, CoinY>(pool);
        pool_state.balance_x.value()
    }

    public fun balance_y<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool_state<CoinX, CoinY>(pool);
        pool_state.balance_y.value()
    }

    public fun admin_balance_x<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool_state<CoinX, CoinY>(pool);
        pool_state.admin_balance_x.value()
    }

    public fun admin_balance_y<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool_state<CoinX, CoinY>(pool);
        pool_state.admin_balance_y.value()
    }

    public use fun pool_swap_fee as FunPool.swap_fee;
    public fun pool_swap_fee<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool_state<CoinX, CoinY>(pool);
        pool_state.swap_fee
    }

    public fun liquidity_x<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool_state<CoinX, CoinY>(pool);
        pool_state.liquidity_x
    }

    public fun liquidity_y<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool_state<CoinX, CoinY>(pool);
        pool_state.liquidity_y
    }

    public fun is_migrating<CoinX, CoinY>(pool: &FunPool): bool {
        let pool_state = pool_state<CoinX, CoinY>(pool);
        pool_state.is_migrating
    }

    public fun is_x_virtual<CoinX, CoinY>(pool: &FunPool): bool {
        let pool_state = pool_state<CoinX, CoinY>(pool);
        pool_state.is_x_virtual
    }

    public fun migration_liquidity_target<CoinX, CoinY>(pool: &FunPool): u64 {
        let pool_state = pool_state<CoinX, CoinY>(pool);
        pool_state.migration_liquidity_target
    }

    public fun migration_witness<CoinX, CoinY>(pool: &FunPool): TypeName {
        let pool_state = pool_state<CoinX, CoinY>(pool);
        pool_state.migration_witness
    }

    public use fun pool_admin as FunPool.admin;
    public fun pool_admin<CoinX, CoinY>(pool: &FunPool): address {
        let pool_state = pool_state<CoinX, CoinY>(pool);
        pool_state.admin
    }

    // === Admin Functions ===

    // === Private Functions ===

    fun new_impl<CoinX, CoinY, Witness>(
        registry: &mut Registry,
        balance_x: Balance<CoinX>,
        balance_y: Balance<CoinY>,
        is_x_virtual: bool,
        ctx: &mut TxContext
    ): FunPool {
        let balance_x_value = balance_x.value();
        let balance_y_value = balance_y.value();

        let virtual_asset_key = if (is_x_virtual) type_name::get<CoinX>() else type_name::get<CoinY>();

        let virtual_liquidity = *registry.initial_virtual_liquidity_config.get(&virtual_asset_key);
        let migration_liquidity_target = *registry.migration_liquidity_config.get(&virtual_asset_key);

        let state = FunPoolState {
            balance_x,
            balance_y,
            admin_balance_x: balance::zero<CoinX>(),
            admin_balance_y: balance::zero<CoinY>(),
            liquidity_x: balance_x_value + if (is_x_virtual) virtual_liquidity else 0,
            liquidity_y: balance_y_value + if (is_x_virtual) 0 else virtual_liquidity,
            swap_fee: registry.swap_fee,
            is_migrating: false,
            is_x_virtual,
            migration_liquidity_target,
            admin: registry.admin,
            migration_witness: type_name::get<Witness>() 
        };

        let mut pool = FunPool {
            id: object::new(ctx)
        };

        df::add(&mut pool.id, StateKey {}, state);

        registry.pools.add(type_name::get<PoolKey<CoinX, CoinY>>(), pool.id.to_address());

        pool
    }

    fun swap_coin_x<CoinX, CoinY>(
        pool: &mut FunPool,
        mut coin_x: Coin<CoinX>,
        coin_y_min_value: u64,
        ctx: &mut TxContext
    ): Coin<CoinY> {
        let pool_state = pool_state_mut<CoinX, CoinY>(pool);
        assert!(!pool_state.is_migrating, errors::pool_is_migrating());

        let coin_in_amount = coin_x.value();
    
        let swap_amount = swap_amounts(
            pool_state, 
            coin_in_amount, 
            coin_y_min_value, 
            true,
        );
        if (swap_amount.fee != 0) {
            pool_state.admin_balance_x.join(coin_x.split(swap_amount.fee, ctx).into_balance());  
        };

        let value_x = coin_x.value();

        pool_state.balance_x.join(coin_x.into_balance());

        pool_state.liquidity_x = pool_state.liquidity_x + value_x;
        pool_state.liquidity_y = pool_state.liquidity_y - swap_amount.amount_out;

        pool_state.may_be_toggle_migrate();

        pool_state.balance_y.split(swap_amount.amount_out).into_coin(ctx) 
    }

    fun swap_coin_y<CoinX, CoinY>(
        pool: &mut FunPool,
        mut coin_y: Coin<CoinY>,
        coin_x_min_value: u64,
        ctx: &mut TxContext
    ): Coin<CoinX> {
        let pool_state = pool_state_mut<CoinX, CoinY>(pool);
        assert!(!pool_state.is_migrating, errors::pool_is_migrating());

        let coin_in_amount = coin_y.value();
        
        let swap_amount = swap_amounts(
            pool_state, 
            coin_in_amount, 
            coin_x_min_value, 
            false
        );

        if (swap_amount.fee != 0) {
            pool_state.admin_balance_y.join(coin_y.split(swap_amount.fee, ctx).into_balance());  
        };

        let value_y = coin_y.value();

        pool_state.balance_y.join(coin_y.into_balance());

        pool_state.liquidity_x = pool_state.liquidity_x - swap_amount.amount_out;
        pool_state.liquidity_y = pool_state.liquidity_y + value_y;

        pool_state.may_be_toggle_migrate();

        pool_state.balance_x.split(swap_amount.amount_out).into_coin(ctx) 
    }  

    fun swap_amounts<CoinX, CoinY>(
        pool_state: &FunPoolState<CoinX, CoinY>,
        coin_in_amount: u64,
        coin_out_min_value: u64,
        is_x: bool
    ): SwapAmount {
        let (balance_x, balance_y) = (
            pool_state.liquidity_x,
            pool_state.liquidity_y
        );

        let prev_k = invariant_(balance_x, balance_y);
        

        let fee = mul_div_up(coin_in_amount, pool_state.swap_fee, FEE_PRECISION);

        let coin_in_amount = coin_in_amount - fee;

        let amount_out =  if (is_x) 
                get_amount_out(coin_in_amount, balance_x, balance_y)
            else 
                get_amount_out(coin_in_amount, balance_y, balance_x);

        assert!(amount_out >= coin_out_min_value, errors::slippage());

        let new_k = if (is_x)
                invariant_(balance_x + coin_in_amount, balance_y - amount_out)
            else
                invariant_(balance_x - amount_out, balance_y + coin_in_amount);

        // @dev impossible to trigger - sanity check
        assert!(new_k >= prev_k, errors::invalid_invariant());

        SwapAmount {
            amount_out,
            fee
        }  
    }

    fun may_be_toggle_migrate<CoinX, CoinY>(state: &mut FunPoolState<CoinX, CoinY>) {
        let liquidity = if (state.is_x_virtual) state.liquidity_y else state.liquidity_x;

        if (liquidity >= state.migration_liquidity_target) state.is_migrating = true;
    }

    fun make_pool_key<CoinA, CoinB>(): TypeName {
        if (utils::is_coin_x<CoinA, CoinB>())
            type_name::get<PoolKey<CoinA, CoinB>>() 
        else 
            type_name::get<PoolKey<CoinB, CoinA>>()
    }

    fun pool_state<CoinX, CoinY>(pool: &FunPool): &FunPoolState<CoinX, CoinY> {
        df::borrow(&pool.id, StateKey {})
    }

    fun pool_state_mut<CoinX, CoinY>(pool: &mut FunPool): &mut FunPoolState<CoinX, CoinY> {
        df::borrow_mut(&mut pool.id,StateKey {})
    }

    // === Test Functions ===
}
