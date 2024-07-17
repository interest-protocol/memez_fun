#[test_only]
module memez_fun::eth {
    use sui::coin;

    public struct ETH has drop {}

    #[lint_allow(share_owned)]
    fun init(witness: ETH, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency<ETH>(
            witness, 
            9, 
            b"ETH",
            b"Ether", 
            b"Ethereum Native Coin", 
            option::none(), 
            ctx
        );

        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::public_share_object(metadata);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ETH {}, ctx);
    }
}

#[test_only]
module memez_fun::usdc {
    use sui::coin;

    public struct USDC has drop {}

    #[lint_allow(share_owned)]
    fun init(witness: USDC, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency<USDC>(
            witness, 
            6, 
            b"USDC",
            b"USD Coin", 
            b"USD Stable Coin by Circle", 
            option::none(), 
            ctx
        );

        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::public_share_object(metadata);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(USDC {}, ctx);
    }
}

#[test_only]
module memez_fun::meme {
    use sui::coin;

    public struct MEME has drop {}

    #[lint_allow(share_owned)]
    fun init(witness: MEME, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency<MEME>(
            witness, 
            9, 
            b"MEME",
            b"MEME", 
            b"Ethereum Native Coin", 
            option::none(), 
            ctx
        );

        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::public_share_object(metadata);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(MEME {}, ctx);
    }
}