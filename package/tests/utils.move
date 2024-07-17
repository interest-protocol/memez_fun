#[test_only]
module memez_fun::tests_utils {

    use sui::{
        sui::SUI,
        test_utils::assert_eq
    };

    use memez_fun::{
        eth::ETH,
        memez_fun_utils::{is_coin_x, are_coins_ordered}
    };

    public struct ABC {}

    public struct CAB {}

    #[test]
    fun test_are_coins_ordered() {
        assert_eq(are_coins_ordered<SUI, ABC>(), true);
        assert_eq(are_coins_ordered<ABC, SUI>(), false);
        assert_eq(are_coins_ordered<ABC, CAB>(), true);
        assert_eq(are_coins_ordered<CAB, ABC>(), false);
    }

    #[test]
    fun test_is_coin_x() {
        assert_eq(is_coin_x<SUI, ABC>(), true);
        assert_eq(is_coin_x<ABC, SUI>(), false);
        assert_eq(is_coin_x<ABC, CAB>(), true);
        assert_eq(is_coin_x<CAB, ABC>(), false);
        // does not throw
        assert_eq(is_coin_x<ETH, ETH>(), false);
    }

    #[test]
    #[expected_failure(abort_code = memez_fun::memez_fun_errors::SAME_COINS_NOT_ALLOWED, location = memez_fun::memez_fun_utils)]
    fun test_are_coins_ordered_error_same_coins_not_allowed() {
        are_coins_ordered<SUI, SUI>();
    }
}