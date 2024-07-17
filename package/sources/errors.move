module memez_fun::memez_fun_errors {

    // === Constants ===

    const SAME_COINS_NOT_ALLOWED: u64 = 0;
    const NO_ZERO_VALUE: u64 = 1;
    const MUST_HAVE_NINE_DECIMALS: u64 = 2;
    const MUST_HAVE_NO_SUPPLY: u64 = 3;
    const CREATE_FEE_IS_TOO_LOW: u64 = 4;
    const NO_CONFIG_AVAILABLE: u64 = 5;
    const POOL_IS_MIGRATING: u64 = 6;
    const SLIPPAGE: u64 = 7;
    const INVALID_INVARIANT: u64 = 8;
    const WITNESS_NOT_WHITELISTED_TO_MIGRATE: u64 = 9;
    const MUST_BE_MIGRATING: u64 = 10;
    const INCORRECT_MIGRATION_WITNESS: u64 = 11;
    const SWAP_FEE_IS_TOO_HIGH: u64 = 12;
    const BURN_PERCENT_IS_TOO_HIGH: u64 = 13;

    // === Public-Package Functions ===

    public(package) fun same_coins_not_allowed(): u64 {
        SAME_COINS_NOT_ALLOWED
    }

    public(package) fun no_zero_value(): u64 {
        NO_ZERO_VALUE
    }

    public(package) fun must_have_nine_decimals(): u64 {
        MUST_HAVE_NINE_DECIMALS
    }

    public(package) fun must_have_no_supply(): u64 {
        MUST_HAVE_NO_SUPPLY
    }

    public(package) fun create_fee_is_too_low(): u64 {
        CREATE_FEE_IS_TOO_LOW
    }

    public(package) fun no_config_available(): u64 {
        NO_CONFIG_AVAILABLE
    }

    public(package) fun pool_is_migrating(): u64 {
        POOL_IS_MIGRATING
    }

    public(package) fun slippage(): u64 {
        SLIPPAGE
    }

    public(package) fun invalid_invariant(): u64 {
        INVALID_INVARIANT
    }

    public(package) fun witness_not_whitelisted_to_migrate(): u64 {
        WITNESS_NOT_WHITELISTED_TO_MIGRATE
    }

    public(package) fun must_be_migrating(): u64 {
        MUST_BE_MIGRATING
    }

    public(package) fun incorrect_migration_witness(): u64 {
        INCORRECT_MIGRATION_WITNESS
    }

    public(package) fun swap_fee_is_too_high(): u64 {
        SWAP_FEE_IS_TOO_HIGH
    }

    public(package) fun burn_percent_is_too_high(): u64 {
        BURN_PERCENT_IS_TOO_HIGH
    }
}
