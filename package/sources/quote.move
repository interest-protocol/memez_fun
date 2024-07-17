module memez_fun::memez_fun_quote {
    // === Imports ===

    use memez_fun::{
        memez_fun::FunPool,
        memez_fun_utils as utils
    };

    use memez_v2_invariant::memez_v2_invariant::get_amount_out;

    use suitears::math64::{mul_div_up, min};

    // === Constants ===

    const FEE_PRECISION: u64 = 1_000_000_000;

    // === Public-View Functions ===

    public fun amount_out<CoinIn, CoinOut>(pool: &FunPool, amount_in: u64): u64 { 

        if (utils::is_coin_x<CoinIn, CoinOut>()) {
            let (liquidity_x, liquidity_y, _, balance_y, swap_fee) = get_pool_data<CoinIn, CoinOut>(pool);
            let fee = mul_div_up(amount_in, swap_fee, FEE_PRECISION);

            min(get_amount_out(amount_in - fee, liquidity_x, liquidity_y), balance_y)
        } else {
            let (liquidity_x, liquidity_y, balance_x, _, swap_fee) = get_pool_data<CoinOut, CoinIn>(pool);
            let fee = mul_div_up(amount_in, swap_fee, FEE_PRECISION);

            min(get_amount_out(amount_in - fee, liquidity_y, liquidity_x), balance_x)
        }
    }

    public fun amount_in<CoinIn, CoinOut>(pool: &FunPool, amount_out: u64): u64 { 

        if (utils::is_coin_x<CoinIn, CoinOut>()) {
            let (liquidity_x, liquidity_y, _, balance_y, swap_fee) = get_pool_data<CoinIn, CoinOut>(pool);

            let amount_out = min(amount_out, balance_y);

            if (amount_out == 0) return 0;

            get_amount_in(amount_out, liquidity_x, liquidity_y, swap_fee)
        } else {
            let (liquidity_x, liquidity_y, balance_x, _, swap_fee) = get_pool_data<CoinOut, CoinIn>(pool);

            let amount_out = min(amount_out, balance_x);

            if (amount_out == 0) return 0;

            get_amount_in(amount_out, liquidity_y, liquidity_x, swap_fee)
        }
    }

    // === Private Functions ===

    fun get_amount_in(amount_out: u64, balance_in: u64, balance_out: u64, fee: u64): u64 {
        let (amount_out, balance_in, balance_out, fee, precision) = (
            (amount_out as u256),
            (balance_in as u256),
            (balance_out as u256),
            (fee as u256),
            (FEE_PRECISION as u256)
        );

        let numerator = balance_in * amount_out * precision;
        let denominator = (balance_out - amount_out) * (precision - fee);
        
        (((numerator / denominator) + 1) as u64)
    }

    fun get_pool_data<CoinX, CoinY>(pool: &FunPool): (u64, u64, u64, u64, u64) {
        let liquidity_x = pool.liquidity_x<CoinX, CoinY>();
        let liquidity_y = pool.liquidity_y<CoinX, CoinY>();
        let balance_x = pool.balance_x<CoinX, CoinY>();
        let balance_y = pool.balance_y<CoinX, CoinY>();
        let swap_fee = pool.swap_fee<CoinX, CoinY>(); 

        (liquidity_x, liquidity_y, balance_x, balance_y, swap_fee)
  }
}
