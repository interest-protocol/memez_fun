#[test_only]
module memez_fun::tests_memez_fun {

    use std::type_name;

    use sui::{
        sui::SUI,
        test_scenario as ts,
        test_utils::{assert_eq, destroy},
        coin::{mint_for_testing, Coin, TreasuryCap, CoinMetadata},
    };

    use suitears::math64::mul_div_up;

    use memez_v2_invariant::memez_v2_invariant::get_amount_out;

    use memez_fun::{
        eth::ETH,
        memez_fun,
        meme::MEME,
        fud::{Self, FUD},
        memez_fun_errors,
        cat::{Self, CAT},
        bonk::{Self, BONK},
        tests_set_up::{start_world, people, witness, IPXWitness}
    };

    const MAX_BURN_PERCENT: u64 = 700_000_000;
    const INITIAL_SWAP_FEE: u64 = 3_000_000;
    const MEME_TOTAL_SUPPLY: u64 = 1_000_000_000_000_000_000;
    const PRECISION: u64 = 1_000_000_000;
    const MAX_SWAP_FEE: u64 = 20_000_000;
    // 20%
    const BURN_PERCENT: u64 = 200_000_000;
    const ADMIN: address = @0xA11c3;
    const DEAD_WALLET: address = @0x0;
    const FIVE_SUI: u64 = 5_000_000_000;

    public struct InvalidWitness has drop {}

    #[test]
    fun test_new() {
        let mut world = start_world();
        let (owner, _) = people();

        assert_eq(world.pool().balance_x<ETH, MEME>(), 0);
        assert_eq(world.pool().balance_y<ETH, MEME>(), MEME_TOTAL_SUPPLY);
        assert_eq(world.pool().admin_balance_x<ETH, MEME>(), 0);
        assert_eq(world.pool().admin_balance_y<ETH, MEME>(), 0);
        assert_eq(world.pool().swap_fee<ETH, MEME>(), INITIAL_SWAP_FEE);
        assert_eq(world.pool().liquidity_x<ETH, MEME>(), 3_000_000_000);
        assert_eq(world.pool().liquidity_y<ETH, MEME>(), MEME_TOTAL_SUPPLY);
        assert_eq(world.pool().is_migrating<ETH, MEME>(), false);
        assert_eq(world.pool().is_x_virtual<ETH, MEME>(), true);
        assert_eq(world.pool().burn_percent<ETH, MEME>(), BURN_PERCENT);
        assert_eq(world.pool().migration_liquidity_target<ETH, MEME>(), 20_000_000_000);
        assert_eq(world.pool().migration_witness<ETH, MEME>(), type_name::get<IPXWitness>());
        assert_eq(world.pool().admin<ETH, MEME>(), ADMIN);
        assert_eq(world.config().pools().length(), 1);
        let pool_address = world.pool().address();
        assert_eq(*world.config().pool_address<ETH, MEME>().borrow(), pool_address);
        assert_eq(world.config().pool_address<CAT, ETH>().is_none(), true);
        assert_eq(world.config().create_fee(), FIVE_SUI);
        assert_eq(world.config().swap_fee(), INITIAL_SWAP_FEE);
        assert_eq(*world.config().initial_virtual_liquidity_config().get(&type_name::get<ETH>()), 3_000_000_000);
        assert_eq(*world.config().migration_liquidity_config().get(&type_name::get<ETH>()), 20_000_000_000);
        assert_eq(world.config().exists_<ETH, MEME>(), true);
        assert_eq(world.config().exists_<CAT, ETH>(), false);
        assert_eq(world.config().admin(), ADMIN);

        world.scenario().next_tx(owner);

        // Proves that we sent to the dead wallet
        let treasury_cap = world.scenario().take_from_address<TreasuryCap<MEME>>(DEAD_WALLET);
        // Creator fee was sent to the admin
        let create_fee = world.scenario().take_from_address<Coin<SUI>>(ADMIN);

        assert_eq(treasury_cap.total_supply(), MEME_TOTAL_SUPPLY);
        assert_eq(create_fee.value(), FIVE_SUI);

        ts::return_to_address(DEAD_WALLET, treasury_cap);
        ts::return_to_address(ADMIN, create_fee);

        world.end();
    }

    #[test]
    fun test_swap() {
        let mut world = start_world();

        let amount_in = 12345678;

        let coin_in = mint_for_testing<MEME>(amount_in, world.scenario().ctx());

        let swap_fee = world.pool().swap_fee<ETH, MEME>();

        let prev_balance_x = world.pool().balance_x<ETH, MEME>();
        let prev_balance_y = world.pool().balance_y<ETH, MEME>();
        let prev_liquidity_x = world.pool().liquidity_x<ETH, MEME>();
        let prev_liquidity_y = world.pool().liquidity_y<ETH, MEME>();

        let fee = mul_div_up(amount_in, swap_fee, PRECISION);

        // Has no ETH
        assert_eq(
            world.swap<MEME, ETH>(coin_in, 0).burn_for_testing(),
            0
        );

        let eth_balance = world.pool().balance_x<ETH, MEME>();
        let meme_balance = world.pool().balance_y<ETH, MEME>();
        let eth_liquidity = world.pool().liquidity_x<ETH, MEME>();
        let meme_liquidity = world.pool().liquidity_y<ETH, MEME>();
        let admin_balance_x = world.pool().admin_balance_x<ETH, MEME>();
        let admin_balance_y = world.pool().admin_balance_y<ETH, MEME>();

        assert_eq(world.pool().is_migrating<ETH, MEME>(), false);
        assert_eq(
            eth_balance,
            prev_balance_x
        );

        assert_eq(
            meme_balance,
            prev_balance_y + amount_in - fee
        );

        assert_eq(
            eth_liquidity,
            prev_liquidity_x
        );

        assert_eq(
            meme_liquidity,
            prev_liquidity_y + amount_in - fee
        );

        assert_eq(
            admin_balance_x,
            0
        );

        assert_eq(
            admin_balance_y,
            fee
        );

        let coin_in = mint_for_testing<ETH>(2 * PRECISION, world.scenario().ctx());
        let fee = mul_div_up(2 * PRECISION, swap_fee, PRECISION);
        let expected_amount_out = get_amount_out((2 * PRECISION) - fee, eth_liquidity, meme_liquidity);

        assert_eq(
            world.swap<ETH, MEME>(coin_in, expected_amount_out).burn_for_testing(),
            expected_amount_out
        );

        assert_eq(world.pool().is_migrating<ETH, MEME>(), false);
        assert_eq(eth_balance + 2 * PRECISION - fee, world.pool().balance_x<ETH, MEME>());
        assert_eq(eth_liquidity + 2 * PRECISION - fee, world.pool().liquidity_x<ETH, MEME>());
        assert_eq(meme_balance - expected_amount_out, world.pool().balance_y<ETH, MEME>());
        assert_eq(meme_liquidity - expected_amount_out, world.pool().liquidity_y<ETH, MEME>());
        assert_eq(admin_balance_x + fee, world.pool().admin_balance_x<ETH, MEME>());
        assert_eq(admin_balance_y, world.pool().admin_balance_y<ETH, MEME>());

        let eth_balance = world.pool().balance_x<ETH, MEME>();
        let meme_balance = world.pool().balance_y<ETH, MEME>();
        let eth_liquidity = world.pool().liquidity_x<ETH, MEME>();
        let meme_liquidity = world.pool().liquidity_y<ETH, MEME>();
        let admin_balance_x = world.pool().admin_balance_x<ETH, MEME>();
        let admin_balance_y = world.pool().admin_balance_y<ETH, MEME>();

        let amount_in = 987654321;
        let coin_in = mint_for_testing<MEME>(amount_in, world.scenario().ctx());
        let fee = mul_div_up(amount_in, swap_fee, PRECISION);
        let expected_amount_out = get_amount_out(amount_in - fee, meme_liquidity, eth_liquidity);

        assert_eq(
            world.swap<MEME, ETH>(coin_in, expected_amount_out).burn_for_testing(),
            expected_amount_out
        );
        assert_eq(world.pool().is_migrating<ETH, MEME>(), false);
        assert_eq(eth_balance - expected_amount_out, world.pool().balance_x<ETH, MEME>());
        assert_eq(eth_liquidity - expected_amount_out, world.pool().liquidity_x<ETH, MEME>());
        assert_eq(meme_balance + amount_in - fee, world.pool().balance_y<ETH, MEME>());
        assert_eq(meme_liquidity + amount_in - fee, world.pool().liquidity_y<ETH, MEME>());
        assert_eq(admin_balance_x, world.pool().admin_balance_x<ETH, MEME>());
        assert_eq(admin_balance_y + fee, world.pool().admin_balance_y<ETH, MEME>());

        let coin_in = mint_for_testing<ETH>(
            mul_div_up((20 * PRECISION - (admin_balance_y + fee)), PRECISION, PRECISION - swap_fee), 
            world.scenario().ctx()
        );
        world.swap<ETH, MEME>(coin_in, 0).burn_for_testing();

        assert_eq(world.pool().is_migrating<ETH, MEME>(), true);

        world.end();     
    }

    #[test]
    fun test_migrate() {
        let mut world = start_world();
        let (owner, _) = people();

        // Trigger migration        
        let coin_in = mint_for_testing<ETH>(25 * PRECISION, world.scenario().ctx());

        world.swap<ETH, MEME>(coin_in, 0).burn_for_testing();

        let admin = world.pool().admin<ETH, MEME>();
        let admin_balance_x = world.pool().admin_balance_x<ETH, MEME>();
        let admin_balance_y = world.pool().admin_balance_y<ETH, MEME>();

        let eth_balance = world.pool().balance_x<ETH, MEME>();
        let meme_balance = world.pool().balance_y<ETH, MEME>();
        let burn_percent = world.pool().burn_percent<ETH, MEME>();

        let (coin_x, coin_y) = world.migrate<ETH, MEME, IPXWitness>(witness());

        let burn_amount = mul_div_up(meme_balance, burn_percent, PRECISION);

        assert_eq(coin_x.burn_for_testing(), eth_balance);
        assert_eq(coin_y.burn_for_testing(), meme_balance - burn_amount);

        world.scenario().next_tx(owner);

        let admin_coin_eth = world.scenario().take_from_address<Coin<ETH>>(admin); 
        let admin_coin_meme = world.scenario().take_from_address<Coin<MEME>>(admin);
        let burnt_meme = world.scenario().take_from_address<Coin<MEME>>(@0x0); 

        assert_eq(admin_coin_eth.burn_for_testing(), admin_balance_x);
        assert_eq(admin_coin_meme.burn_for_testing(), admin_balance_y);
        assert_eq(burnt_meme.burn_for_testing(), burn_amount);

        world.end();
    }

    #[test]
    fun test_new_y_virtual_liquidity() {
        let mut world = start_world();
        let (owner, _) = people();

        cat::init_for_testing(world.scenario().ctx());

        world.scenario().next_tx(owner);

        let cat_treasury_cap = world.scenario().take_from_sender<TreasuryCap<CAT>>(); 
        let metadata_cat = world.scenario().take_shared<CoinMetadata<CAT>>();

        let create_fee = mint_for_testing(5_000_000_000, world.scenario().ctx());

       let pool = world.new<CAT, ETH, IPXWitness>(
            cat_treasury_cap,
            &metadata_cat,
            create_fee,
            BURN_PERCENT
        );

        assert_eq(pool.balance_x<CAT, ETH>(), MEME_TOTAL_SUPPLY);
        assert_eq(pool.balance_y<CAT, ETH>(), 0);
        assert_eq(pool.liquidity_x<CAT, ETH>(), MEME_TOTAL_SUPPLY);
        assert_eq(pool.liquidity_y<CAT, ETH>(), 3_000_000_000);
        assert_eq(pool.is_x_virtual<CAT, ETH>(), false);

        pool.share();

        destroy(metadata_cat);

        world.end();
    }

    #[test]
    fun test_migrate_y_virtual_liquidity() {
        let mut world = start_world();
        let (owner, _) = people();

        cat::init_for_testing(world.scenario().ctx());

        world.scenario().next_tx(owner);

        let cat_treasury_cap = world.scenario().take_from_sender<TreasuryCap<CAT>>(); 
        let metadata_cat = world.scenario().take_shared<CoinMetadata<CAT>>();

        let create_fee = mint_for_testing(5_000_000_000, world.scenario().ctx());

       let mut pool = world.new<CAT, ETH, IPXWitness>(
            cat_treasury_cap,
            &metadata_cat,
            create_fee,
            BURN_PERCENT
        );

        ts::return_shared(metadata_cat);

        world.scenario().next_tx(owner);

        assert_eq(pool.is_x_virtual<CAT, ETH>(), false);

        // Trigger migration        
        let coin_in = mint_for_testing<ETH>(30 * PRECISION, world.scenario().ctx());
    
        destroy(memez_fun::swap<ETH, CAT>(&mut pool, coin_in, 0, world.scenario().ctx()));
        
        let burn_percent = pool.burn_percent<CAT, ETH>();
        let meme_balance = pool.balance_x<CAT, ETH>();
        let burn_amount = mul_div_up(meme_balance, burn_percent, PRECISION);

        let (coin_x, coin_y) = memez_fun::migrate<CAT, ETH, IPXWitness>(
            pool, witness(), 
            world.scenario().ctx()
        );

        coin_x.burn_for_testing();
        coin_y.burn_for_testing();

        world.scenario().next_tx(owner);

        let burnt_meme = world.scenario().take_from_address<Coin<CAT>>(@0x0);

        assert_eq(burnt_meme.burn_for_testing(), burn_amount);

        world.end();
    }

    #[test]
    fun test_migrator_admin_fns() {
        let mut world = start_world();

        let name = type_name::get<InvalidWitness>();

        assert_eq(world.config().whitelist().contains(&name), false);

        world.add_migrator<InvalidWitness>();

        assert_eq(world.config().whitelist().contains(&name), true);

        world.remove_migrator<InvalidWitness>();

        assert_eq(world.config().whitelist().contains(&name), false);

        world.end();
    }

    #[test]
    fun test_admin_fns() {
        let mut world = start_world();

        let swap_fee = world.config().swap_fee();

        assert_eq(swap_fee, INITIAL_SWAP_FEE);
        
        world.update_swap_fee(MAX_SWAP_FEE);

        let swap_fee = world.config().swap_fee();

        assert_eq(swap_fee, MAX_SWAP_FEE);

        let create_fee = world.config().create_fee();

        assert_eq(create_fee, FIVE_SUI);

        world.update_create_fee(FIVE_SUI * 3);

        let create_fee = world.config().create_fee();

        assert_eq(create_fee, FIVE_SUI * 3);

        let admin = world.config().admin();

        assert_eq(admin, ADMIN);

        world.update_admin(@0x2);

        let admin = world.config().admin();

        assert_eq(admin, @0x2);

        let coin_in = mint_for_testing(2_000_000_000, world.scenario().ctx());
        world.swap<ETH, MEME>(coin_in, 0).burn_for_testing();
        let coin_in = mint_for_testing(2_000_000_000, world.scenario().ctx());
        world.swap<ETH, MEME>(coin_in, 0).burn_for_testing();
        let coin_in = mint_for_testing(2_000_000_000, world.scenario().ctx());
        world.swap<ETH, MEME>(coin_in, 0).burn_for_testing();
        let coin_in = mint_for_testing(2_000_000_000, world.scenario().ctx());
        world.swap<ETH, MEME>(coin_in, 0).burn_for_testing();

        let coin_in = mint_for_testing(250_000_000_000, world.scenario().ctx());
        world.swap<MEME, ETH>(coin_in, 0).burn_for_testing();
        let coin_in = mint_for_testing(250_000_000_000, world.scenario().ctx());
        world.swap<MEME, ETH>(coin_in, 0).burn_for_testing();
        let coin_in = mint_for_testing(250_000_000_000, world.scenario().ctx());
        world.swap<MEME, ETH>(coin_in, 0).burn_for_testing();

        let admin_balance_x = world.pool().admin_balance_x<ETH, MEME>();
        let admin_balance_y = world.pool().admin_balance_y<ETH, MEME>();

        assert_eq(admin_balance_x > 0, true);
        assert_eq(admin_balance_y > 0, true);
 
        let (coin_eth, coin_meme) = world.take_fees<ETH, MEME>();

        assert_eq(coin_eth.burn_for_testing(), admin_balance_x);
        assert_eq(coin_meme.burn_for_testing(), admin_balance_y);

        let admin_balance_x = world.pool().admin_balance_x<ETH, MEME>();
        let admin_balance_y = world.pool().admin_balance_y<ETH, MEME>();

        assert_eq(admin_balance_x, 0);
        assert_eq(admin_balance_y, 0);

        let (coin_eth, coin_meme) = world.take_fees<ETH, MEME>();

        assert_eq(coin_eth.burn_for_testing(), admin_balance_x);
        assert_eq(coin_meme.burn_for_testing(), admin_balance_y);

        world.end();
    }

    #[test]
    fun test_make_pool_key() {
        let key1 = memez_fun::make_pool_key_for_testing<ETH, MEME>();
        let key2 = memez_fun::make_pool_key_for_testing<MEME, ETH>();

        assert_eq(key1, key2);

        let key1 = memez_fun::make_pool_key_for_testing<ETH, CAT>();
        let key2 = memez_fun::make_pool_key_for_testing<CAT, ETH>();

        assert_eq(key1, key2);
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::NO_ZERO_VALUE, location = memez_fun)]
    fun test_swap_error_no_zero_value() {
        let mut world = start_world();

        let coin_in = mint_for_testing<MEME>(0, world.scenario().ctx());

        world.swap<MEME, ETH>(coin_in, 0).burn_for_testing();

        world.end();     
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::SLIPPAGE, location = memez_fun)]
    fun test_swap_x_error_slippage() {
        let mut world = start_world();

        let eth_liquidity = world.pool().liquidity_x<ETH, MEME>();
        let meme_liquidity = world.pool().liquidity_y<ETH, MEME>();
        let swap_fee = world.pool().swap_fee<ETH, MEME>();

        let coin_in = mint_for_testing<ETH>(2 * PRECISION, world.scenario().ctx());
        let fee = mul_div_up(2 * PRECISION, swap_fee, PRECISION);
        let expected_amount_out = get_amount_out((2 * PRECISION) - fee, eth_liquidity, meme_liquidity);

        world.swap<ETH, MEME>(coin_in, expected_amount_out + 1).burn_for_testing();

        world.end();     
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::SLIPPAGE, location = memez_fun)]
    fun test_swap_y_error_slippage() {
        let mut world = start_world();

        let eth_liquidity = world.pool().liquidity_x<ETH, MEME>();
        let meme_liquidity = world.pool().liquidity_y<ETH, MEME>();
        let swap_fee = world.pool().swap_fee<ETH, MEME>();

        let coin_in = mint_for_testing<MEME>(200 * PRECISION, world.scenario().ctx());
        let fee = mul_div_up(200 * PRECISION, swap_fee, PRECISION);
        let expected_amount_out = get_amount_out((200 * PRECISION) - fee, eth_liquidity, meme_liquidity);

        world.swap<MEME, ETH>(coin_in, expected_amount_out + 1).burn_for_testing();

        world.end();     
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::POOL_IS_MIGRATING, location = memez_fun)]
    fun test_swap_error_is_migrating_swap_x() {
        let mut world = start_world();

        let coin_in = mint_for_testing<ETH>(25 * PRECISION, world.scenario().ctx());

        world.swap<ETH, MEME>(coin_in, 0).burn_for_testing();

        let coin_in = mint_for_testing<ETH>(1, world.scenario().ctx());
        world.swap<ETH, MEME>(coin_in, 0).burn_for_testing();

        world.end();     
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::POOL_IS_MIGRATING, location = memez_fun)]
    fun test_swap_error_is_migrating_swap_y() {
        let mut world = start_world();

        let coin_in = mint_for_testing<ETH>(25 * PRECISION, world.scenario().ctx());

        world.swap<ETH, MEME>(coin_in, 0).burn_for_testing();

        let coin_in = mint_for_testing<MEME>(1, world.scenario().ctx());
        world.swap<MEME, ETH>(coin_in, 0).burn_for_testing();

        world.end();     
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::WITNESS_NOT_WHITELISTED_TO_MIGRATE, location = memez_fun)]
    fun test_new_error_witness_not_whitelisted_to_migrate() {
        let mut world = start_world();
        let (owner, _) = people();

        world.scenario().next_tx(owner);

        fud::init_for_testing(world.scenario().ctx());

        world.scenario().next_tx(owner);

        let meme_tc = world.scenario().take_from_sender<TreasuryCap<FUD>>();
        let meme_metadata = world.scenario().take_shared<CoinMetadata<FUD>>();

        let sui_in = mint_for_testing<SUI>(5_000_000_000, world.scenario().ctx());

        destroy(world.new<FUD, ETH, InvalidWitness>(
            meme_tc,
            &meme_metadata,
            sui_in,
            BURN_PERCENT,
        ));

        destroy(meme_metadata);

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::MUST_HAVE_NO_SUPPLY, location = memez_fun)]
    fun test_new_error_must_have_no_supply() {
        let mut world = start_world();
        let (owner, _) = people();

        world.scenario().next_tx(owner);

        fud::init_for_testing(world.scenario().ctx());

        world.scenario().next_tx(owner);

        let mut meme_tc = world.scenario().take_from_sender<TreasuryCap<FUD>>();
        let meme_metadata = world.scenario().take_shared<CoinMetadata<FUD>>();

        let sui_in = mint_for_testing<SUI>(5_000_000_000, world.scenario().ctx());

        destroy(meme_tc.mint(1, world.scenario().ctx()));

        destroy(world.new<FUD, ETH, IPXWitness>(
            meme_tc,
            &meme_metadata,
            sui_in,
            BURN_PERCENT,
        ));

        destroy(meme_metadata);

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::MUST_HAVE_NINE_DECIMALS, location = memez_fun)]
    fun test_new_error_must_have_nine_decimals() {
        let mut world = start_world();
        let (owner, _) = people();

        world.scenario().next_tx(owner);

        bonk::init_for_testing(world.scenario().ctx());

        world.scenario().next_tx(owner);

        let meme_tc = world.scenario().take_from_sender<TreasuryCap<BONK>>();
        let meme_metadata = world.scenario().take_shared<CoinMetadata<BONK>>();

        let sui_in = mint_for_testing<SUI>(5_000_000_000, world.scenario().ctx());

        destroy(world.new<BONK, ETH, IPXWitness>(
            meme_tc,
            &meme_metadata,
            sui_in,
            BURN_PERCENT,
        ));

        destroy(meme_metadata);

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::CREATE_FEE_IS_TOO_LOW, location = memez_fun)]
    fun test_new_error_create_fee_is_too_low() {
        let mut world = start_world();
        let (owner, _) = people();

        world.scenario().next_tx(owner);

        fud::init_for_testing(world.scenario().ctx());

        world.scenario().next_tx(owner);

        let meme_tc = world.scenario().take_from_sender<TreasuryCap<FUD>>();
        let meme_metadata = world.scenario().take_shared<CoinMetadata<FUD>>();

        let sui_in = mint_for_testing<SUI>(5_000_000_000 - 1, world.scenario().ctx());

        destroy(world.new<FUD, ETH, IPXWitness>(
            meme_tc,
            &meme_metadata,
            sui_in,
            BURN_PERCENT,
        ));

        destroy(meme_metadata);

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::NO_CONFIG_AVAILABLE, location = memez_fun)]
    fun test_new_error_no_initial_virtual_liquidity_config() {
        let mut world = start_world();
        let (owner, _) = people();

        world.scenario().next_tx(owner);

        fud::init_for_testing(world.scenario().ctx());

        world.scenario().next_tx(owner);

        let meme_tc = world.scenario().take_from_sender<TreasuryCap<FUD>>();
        let meme_metadata = world.scenario().take_shared<CoinMetadata<FUD>>();

        let sui_in = mint_for_testing<SUI>(5_000_000_000, world.scenario().ctx());

        world.update_migration_liquidity<ETH>(1);

        destroy(world.new<FUD, SUI, IPXWitness>(
            meme_tc,
            &meme_metadata,
            sui_in,
            BURN_PERCENT,
        ));

        destroy(meme_metadata);

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::NO_CONFIG_AVAILABLE, location = memez_fun)]
    fun test_new_error_migration_liquidity_config() {
        let mut world = start_world();
        let (owner, _) = people();

        world.scenario().next_tx(owner);

        fud::init_for_testing(world.scenario().ctx());

        world.scenario().next_tx(owner);

        let meme_tc = world.scenario().take_from_sender<TreasuryCap<FUD>>();
        let meme_metadata = world.scenario().take_shared<CoinMetadata<FUD>>();

        let sui_in = mint_for_testing<SUI>(5_000_000_000, world.scenario().ctx());

        world.update_initial_virtual_liquidity<ETH>(1);

        destroy(world.new<FUD, SUI, IPXWitness>(
            meme_tc,
            &meme_metadata,
            sui_in,
            BURN_PERCENT,
        ));

        destroy(meme_metadata);

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::BURN_PERCENT_IS_TOO_HIGH, location = memez_fun)]
    fun test_new_error_burn_percent_is_too_high() {
        let mut world = start_world();
        let (owner, _) = people();

        world.scenario().next_tx(owner);

        fud::init_for_testing(world.scenario().ctx());

        world.scenario().next_tx(owner);

        let meme_tc = world.scenario().take_from_sender<TreasuryCap<FUD>>();
        let meme_metadata = world.scenario().take_shared<CoinMetadata<FUD>>();

        let sui_in = mint_for_testing<SUI>(5_000_000_000, world.scenario().ctx());

        destroy(world.new<FUD, ETH, IPXWitness>(
            meme_tc,
            &meme_metadata,
            sui_in,
            MAX_BURN_PERCENT + 1,
        ));

        destroy(meme_metadata);

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::INCORRECT_MIGRATION_WITNESS, location = memez_fun)]
    fun test_migrate_error_incorrect_migration_witness() {
        let mut world = start_world();

        // Trigger migration        
        let coin_in = mint_for_testing<ETH>(25 * PRECISION, world.scenario().ctx());

        world.swap<ETH, MEME>(coin_in, 0).burn_for_testing();

        let (coin_x, coin_y) = world.migrate<ETH, MEME, InvalidWitness>(InvalidWitness {});

        coin_x.burn_for_testing();
        coin_y.burn_for_testing();

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::SWAP_FEE_IS_TOO_HIGH, location = memez_fun)]
    fun test_update_swap_fee_error_fee_is_too_high() {
        let mut world = start_world();

        world.update_swap_fee(MAX_SWAP_FEE + 1);

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = memez_fun_errors::MUST_BE_MIGRATING, location = memez_fun)]
    fun test_migrate_error_must_be_migrating() {
        let mut world = start_world();

        // Trigger migration        
        let coin_in = mint_for_testing<ETH>(10 * PRECISION, world.scenario().ctx());

        world.swap<ETH, MEME>(coin_in, 0).burn_for_testing();

        let (coin_x, coin_y) = world.migrate<ETH, MEME, IPXWitness>(witness());

        coin_x.burn_for_testing();
        coin_y.burn_for_testing();

        world.end();
    }
}
