#[test_only]
module memez_fun::memez_fun_tests_set_up {
    // === Imports ===

    use sui::{
        coin::Coin,
        test_utils::destroy,
        test_scenario::{Self as ts, Scenario},
        coin::{Self, TreasuryCap, CoinMetadata},
    };

    use memez_fun::{
        eth::{Self, ETH},
        usdc::{Self, USDC},
        meme::{Self, MEME},
        memez_fun::{Self, FunPool, Admin, Config},
    };

    // === Constants ===

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xA11c3;
    // 20%
    const BURN_PERCENT: u64 = 200_000_000;

    // === Structs ===

    public struct AFWitness has drop {}

    public struct IPXWitness has drop {}

    public struct World {
        pool: FunPool,
        scenario: Scenario,
        config: Config,
        admin: Admin,
        eth_tc: TreasuryCap<ETH>,
        usdc_tc: TreasuryCap<USDC>,
    }

    public fun start_world(): World {
        let mut scenario = ts::begin(OWNER);

        scenario.next_tx(OWNER);

        memez_fun::init_for_testing(scenario.ctx());
        eth::init_for_testing(scenario.ctx());
        usdc::init_for_testing(scenario.ctx());
        meme::init_for_testing(scenario.ctx());

        scenario.next_tx(OWNER);

        let eth_tc = scenario.take_from_sender<TreasuryCap<ETH>>();
        let usdc_tc = scenario.take_from_sender<TreasuryCap<USDC>>();
        let meme_tc = scenario.take_from_sender<TreasuryCap<MEME>>();
        let meme_metadata = scenario.take_shared<CoinMetadata<MEME>>();
        let admin = scenario.take_from_sender<Admin>();
        let mut config = scenario.take_shared<Config>();

        config.add_migrator<IPXWitness>(&admin);
        // 3 ETH
        config.update_initial_virtual_liquidity<ETH>(&admin, 3_000_000_000);
        // 20 ETH
        config.update_migration_liquidity<ETH>(&admin, 20_000_000_000);

        let pool = memez_fun::new<MEME, ETH, IPXWitness>(
            &mut config,
            meme_tc,
            &meme_metadata,
            coin::mint_for_testing(5_000_000_000, scenario.ctx()),
            BURN_PERCENT,
            scenario.ctx()
        );

        ts::return_shared(meme_metadata);

        World {
            pool,
            scenario,
            config,
            admin,
            eth_tc,
            usdc_tc
        }
    }

    public fun swap<CoinIn, CoinOut>(self: &mut World, coin_in: Coin<CoinIn>, min_amount_out: u64): Coin<CoinOut> {
        self.pool.swap<CoinIn, CoinOut>(
            coin_in,
            min_amount_out,
            self.scenario.ctx()
        )
    }

    public fun pool(self: &mut World): &mut FunPool {
        &mut self.pool
    }

    public fun config(self: &mut World): &mut Config {
        &mut self.config
    }

    public fun scenario(self: &mut World): &mut Scenario {
        &mut self.scenario
    }

    public fun admin(self: &mut World): &mut Admin {
        &mut self.admin
    }

    public fun end(self: World) {
        destroy(self);
    }

    public fun people(): (address, address) {
        (OWNER, ALICE)
    }
}
