module memez_fun::memez_fun_utils {
    // === Imports ===

    use std::type_name;

    use suitears::comparator;

    use memez_fun::memez_fun_errors as errors;

    // === Public-View Functions ===

    public fun are_coins_ordered<CoinA, CoinB>(): bool {
        let coin_a_type_name = type_name::get<CoinA>();
        let coin_b_type_name = type_name::get<CoinB>();
    
        assert!(coin_a_type_name != coin_b_type_name, errors::same_coins_not_allowed());
    
        comparator::compare(&coin_a_type_name, &coin_b_type_name).lt()
    }

    // === Public-Package Functions ===

    public(package) fun is_coin_x<CoinA, CoinB>(): bool {
        comparator::compare(&type_name::get<CoinA>(), &type_name::get<CoinB>()).lt()
    }
}
