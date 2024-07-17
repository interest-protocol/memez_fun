#[test_only]
module memez_fun::tests_quote {

    use sui::{
        test_utils::assert_eq,
        coin::{mint_for_testing, burn_for_testing},
    };

    use suitears::math64::{mul_div_up, min};

    use memez_v2_invariant::memez_v2_invariant::{get_amount_in, get_amount_out};

    use memez_fun::{
        eth::ETH,
        meme::MEME,
        memez_fun_quote,
        tests_set_up::start_world
    };

    const PRECISION: u64 = 1_000_000_000;

    #[test]
    fun test_amount_out() {

        let mut world = start_world();

        // 0.1 ETH
        let eth_amount_in = 200_000_000;
        // 5 MEME
        let meme_amount_in = 5_000_000_000;

        let quote_amount = memez_fun_quote::amount_out<MEME, ETH>(world.pool(), meme_amount_in);

        assert_eq(quote_amount, 0);

        let quote_amount = memez_fun_quote::amount_out<ETH, MEME>(world.pool(), eth_amount_in);

        let liquidity_eth = world.pool().liquidity_x<ETH, MEME>();
        let liquidity_meme = world.pool().liquidity_y<ETH, MEME>();
        let fee_percent = world.pool().swap_fee<ETH, MEME>();

        let expected_amount_out = get_amount_out(
            eth_amount_in - mul_div_up(eth_amount_in, fee_percent, PRECISION), 
            liquidity_eth, 
            liquidity_meme
        );

        assert_eq(quote_amount, expected_amount_out);

        let coin_in = mint_for_testing<ETH>(eth_amount_in, world.scenario().ctx());

        let coin_out = world.swap<ETH, MEME>(
            coin_in,
            expected_amount_out
        );

        assert_eq(coin_out.burn_for_testing(), expected_amount_out);

        let meme_amount_in = 1234567;
        let fee =  mul_div_up(meme_amount_in, fee_percent, PRECISION);

        let coin_in = mint_for_testing<MEME>(meme_amount_in, world.scenario().ctx()); 

        let expected_amount_out = get_amount_out(
            meme_amount_in - fee, 
            liquidity_meme,
            liquidity_eth
        );

        let coin_out = world.swap<MEME, ETH>(
            coin_in,
            expected_amount_out
        );

        assert_eq(coin_out.burn_for_testing(), expected_amount_out);

        world.end();
    }

    #[test]
    fun test_amount_in() {

        let mut world = start_world();

        // 0.1 ETH
        let eth_amount_out = 200_000_000;
        // 5 MEME
        let meme_amount_out = 5_000_000_000;

        // Pool does not have any ETH to get out
        let quote_amount = memez_fun_quote::amount_in<MEME, ETH>(world.pool(), eth_amount_out);

        assert_eq(quote_amount, 0);

        let expected_amount_in = memez_fun_quote::amount_in<ETH, MEME>(world.pool(), meme_amount_out);

        let coin_in = mint_for_testing<ETH>(expected_amount_in, world.scenario().ctx()); 

        let coin_out = world.swap<ETH, MEME>(
            coin_in,
            0
        );

        assert_within_1_percent(meme_amount_out, coin_out.burn_for_testing());

        let expected_amount_in = memez_fun_quote::amount_in<MEME, ETH>(world.pool(), 123);

        let liquidity_eth = world.pool().liquidity_x<ETH, MEME>();
        let liquidity_meme = world.pool().liquidity_y<ETH, MEME>();
        let balance_eth = world.pool().balance_x<ETH, MEME>();
        let fee_percent = world.pool().swap_fee<ETH, MEME>();

        let amount_in = get_amount_in(min(123, balance_eth), liquidity_meme, liquidity_eth);

        let amount_in = mul_div_up(amount_in, PRECISION, PRECISION - fee_percent) - 1;

        assert_eq(amount_in, expected_amount_in);

        let expected_amount_in = memez_fun_quote::amount_in<MEME, ETH>(world.pool(), 10);
        let amount_in = get_amount_in(10, liquidity_meme, liquidity_eth);

        let amount_in = mul_div_up(amount_in, PRECISION, PRECISION - fee_percent) - 1;

        assert_eq(amount_in, expected_amount_in);

        world.end();
    }

    fun assert_within_1_percent(x: u64, y: u64) {
        let v = mul_div_up(10000000, x, PRECISION);
        
        assert_eq(y >= x - v && x + v >= y, true);
    }
}