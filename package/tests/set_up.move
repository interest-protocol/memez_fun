#[test_only]
module memez_fun::tests_set_up {
    // === Imports ===

    use sui::{
        sui::SUI,
        coin::Coin,
        test_utils::destroy,
        test_scenario::{Self as ts, Scenario},
        coin::{Self, TreasuryCap, CoinMetadata},
    };

    use memez_fun::{
        eth::{Self, ETH},
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

    public struct IPXWitness has drop, copy {}

    public struct World {
        pool: vector<FunPool>,
        scenario: Scenario,
        config: Config,
        admin: Admin,
        eth_tc: TreasuryCap<ETH>,
    }

    public fun start_world(): World {
        let mut scenario = ts::begin(OWNER);

        scenario.next_tx(OWNER);

        memez_fun::init_for_testing(scenario.ctx());
        eth::init_for_testing(scenario.ctx());
        meme::init_for_testing(scenario.ctx());

        scenario.next_tx(OWNER);

        let eth_tc = scenario.take_from_sender<TreasuryCap<ETH>>();
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
            pool: vector[pool],
            scenario,
            config,
            admin,
            eth_tc
        }
    }

    public fun new<CoinA, CoinB, Witness: drop>(
        self: &mut World, 
        treasury_cap: TreasuryCap<CoinA>,
        metadata: &CoinMetadata<CoinA>,
        create_fee: Coin<SUI>, 
        burn_percent: u64
    ): FunPool {
        memez_fun::new<CoinA, CoinB, Witness>(
            &mut self.config,
            treasury_cap,
            metadata,
            create_fee,
            burn_percent,
            self.scenario.ctx()
        )
    }

    public fun swap<CoinIn, CoinOut>(self: &mut World, coin_in: Coin<CoinIn>, min_amount_out: u64): Coin<CoinOut> {
        self.pool[0].swap<CoinIn, CoinOut>(
            coin_in,
            min_amount_out,
            self.scenario.ctx()
        )
    }

    public fun migrate<CoinX, CoinY, Witness: drop>(self: &mut World, witness: Witness): (Coin<CoinX>, Coin<CoinY>) {
        let pool = self.pool.pop_back();
        pool.migrate<CoinX, CoinY, Witness>(
            witness,
            self.scenario.ctx()
        )
    }

    public fun take_fees<CoinX, CoinY>(self: &mut World): (Coin<CoinX>, Coin<CoinY>) {
        self.pool[0].take_fees(&self.admin, self.scenario.ctx())
    }

    public fun update_admin(self: &mut World, admin: address) {
        self.config.update_admin(&self.admin, admin)
    }

    public fun update_create_fee(self: &mut World, fee: u64) {
        self.config.update_create_fee(&self.admin, fee)
    }

    public fun update_swap_fee(self: &mut World, fee: u64) {
        self.config.update_swap_fee(&self.admin, fee)
    }

    public fun update_initial_virtual_liquidity<CoinType>(self: &mut World, liquidity: u64) {
        self.config.update_initial_virtual_liquidity<CoinType>(&self.admin, liquidity);
    }

    public fun update_migration_liquidity<CoinType>(self: &mut World, liquidity: u64) {
        self.config.update_migration_liquidity<CoinType>(&self.admin, liquidity);
    }

    public fun add_migrator<Witness>(self: &mut World) {
        self.config.add_migrator<Witness>(&self.admin);
    }

    public fun remove_migrator<Witness>(self: &mut World) {
        self.config.remove_migrator<Witness>(&self.admin);
    }

    public fun pool(self: &mut World): &mut FunPool {
        &mut self.pool[0]
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

    public fun witness(): IPXWitness {
        IPXWitness {}
    }

    public fun end(self: World) {
        destroy(self);
    }

    public fun people(): (address, address) {
        (OWNER, ALICE)
    }
}
