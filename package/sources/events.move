module memez_fun::memez_fun_events {
    // === Imports ===

    use std::type_name::TypeName;

    use sui::event::emit;

    // === Structs ===

    public struct NewFunPool has copy, drop, store {
        pool: address,
        coin_x: TypeName,
        coin_y: TypeName,
        balance_x: u64,
        balance_y: u64,
        liquidity_x: u64,
        liquidity_y: u64,
        is_x_virtual: bool,
        migration_witness: TypeName
    }

    public struct Swap has copy, drop, store {
        pool: address,
        coin_in: TypeName,
        coin_out: TypeName,
        amount_in: u64,
        amount_out: u64,
        fee: u64
    }

    public struct ReadyForMigration has copy, drop, store {
        pool: address,
        coin_x: TypeName,
        coin_y: TypeName,
        migration_witness: TypeName
    }

    public struct Migrated has copy, drop, store {
        pool: address,
        coin_x: TypeName,
        coin_y: TypeName,
        amount_x: u64,
        amount_y: u64,
        admin_x: u64,
        admin_y: u64,
        migration_witness: TypeName
    }

    // === Public-Package Functions ===

    public(package) fun new_fun_pool(
        pool: address,
        coin_x: TypeName,
        coin_y: TypeName,
        balance_x: u64,
        balance_y: u64,
        liquidity_x: u64,
        liquidity_y: u64,
        is_x_virtual: bool,
        migration_witness: TypeName
    ) {
        emit(
            NewFunPool {
                pool,
                coin_x,
                coin_y,
                balance_x,
                balance_y,
                liquidity_x,
                liquidity_y,
                is_x_virtual,
                migration_witness
            }
        );
    }

    public(package) fun swap(
        pool: address,
        coin_in: TypeName,
        coin_out: TypeName,
        amount_in: u64,
        amount_out: u64,
        fee: u64
    ) {
        emit(
            Swap {
                pool,
                coin_in,
                coin_out,
                amount_in,
                amount_out,
                fee
            }
        );
    }

    public(package) fun ready_for_migration(
        pool: address,
        coin_x: TypeName,
        coin_y: TypeName,
        migration_witness: TypeName
    ) {
        emit(
            ReadyForMigration {
                pool,
                coin_x,
                coin_y,
                migration_witness
            }
        );
    }

    public(package) fun migrated(
        pool: address,
        coin_x: TypeName,
        coin_y: TypeName,
        amount_x: u64,
        amount_y: u64,
        admin_x: u64,
        admin_y: u64,
        migration_witness: TypeName
    ) {
        emit(
            Migrated {
                pool,
                coin_x,
                coin_y,
                amount_x,
                amount_y,
                admin_x,
                admin_y,
                migration_witness
            }
        );
    }
}
