module memez_fun::memez_fun_quote {
    // === Imports ===

    use memez_fun::{
        memez_fun::FunPool,
        memez_fun_utils as utils
    };

    use memez_v2_invariant::memez_v2_invariant::{get_amount_in, get_amount_out};

    use suitears::math64::mul_div_up;

    // === Constants ===

    const FEE_PRECISION: u64 = 1_000_000_000;

    // === Public-View Functions ===

    public fun amount_out<CoinIn, CoinOut>(pool: &FunPool, amount_in: u64): u64 { 

        if (utils::is_coin_x<CoinIn, CoinOut>()) {
            let (balance_x, balance_y, swap_fee) = get_pool_data<CoinIn, CoinOut>(pool);
            let fee = mul_div_up(amount_in, swap_fee, FEE_PRECISION);

            get_amount_out(amount_in - fee, balance_x, balance_y)
        } else {
            let (balance_x, balance_y, swap_fee) = get_pool_data<CoinOut, CoinIn>(pool);
            let fee = mul_div_up(amount_in, swap_fee, FEE_PRECISION);

            get_amount_out(amount_in - fee, balance_y, balance_x)
        }
    }

    public fun amount_in<CoinIn, CoinOut>(pool: &FunPool, amount_out: u64): u64 { 

        if (utils::is_coin_x<CoinIn, CoinOut>()) {
            let (balance_x, balance_y, swap_fee) = get_pool_data<CoinIn, CoinOut>(pool);

            get_initial_amount(get_amount_in(amount_out, balance_x, balance_y), swap_fee)
        } else {
            let (balance_x, balance_y, swap_fee) = get_pool_data<CoinOut, CoinIn>(pool);

            get_initial_amount(get_amount_in(amount_out, balance_y, balance_x), swap_fee)
        }
    }

    // === Private Functions ===

    fun get_initial_amount(x: u64, percent: u64): u64 {
        mul_div_up(x, FEE_PRECISION, FEE_PRECISION - percent)
    }

    fun get_pool_data<CoinX, CoinY>(pool: &FunPool): (u64, u64, u64) {
        let liquidity_x = pool.liquidity_x<CoinX, CoinY>();
        let liquidity_y = pool.liquidity_y<CoinX, CoinY>();
        let swap_fee = pool.swap_fee<CoinX, CoinY>(); 

        (liquidity_x, liquidity_y, swap_fee)
  }
}
