use starknet::{ContractAddress};
use crate::SBT::SBT::{Team};

#[starknet::interface]
pub trait ISBT<TContractState> {
    // mint your own avatar
    fn mint(ref self: TContractState);
    fn get_user_team(self: @TContractState, user: ContractAddress) -> Team;
    fn has_token(self: @TContractState, user: ContractAddress) -> bool;
    // ERC721 overrides
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn token_uri(self: @TContractState, token_id: u256) -> ByteArray;
}

#[starknet::contract]
pub mod SBT {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::ERC721Component::ERC721HooksTrait;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::{get_block_timestamp, get_caller_address, ContractAddress};
    use starknet::storage::{Map, StoragePathEntry};
    use core::num::traits::Zero;
    use super::{ISBT};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    // Don't embed entire ERC721 ABI because we need to override some methods
    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnlyImpl = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
    impl ERC721MetadataImpl = ERC721Component::ERC721MetadataImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        SBTMinted: SBTMinted,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }
    #[derive(Drop, starknet::Event)]
    pub struct SBTMinted {
        pub user: ContractAddress,
        pub token_id: u256,
        pub team: Team,
    }

    #[storage]
    struct Storage {
        // token_id -> team
        user_team: Map<felt252, Team>,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[derive(Debug, Copy, Drop, PartialEq, Serde, starknet::Store)]
    pub enum Team {
        BlueFox,
        RedWolf,
        GreenApple
    }

    pub mod Errors {
        pub const INVALID_ADDRESS: felt252 = 'Invalid address';
        pub const TOKEN_ALREADY_OWNED: felt252 = 'Token already owned by caller';
        pub const NO_TOKEN_OWNED: felt252 = 'No token owned by user';
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, base_uri: ByteArray) {
        self.erc721.initializer("SBT", "SBT", base_uri);
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl SBTImpl of ISBT<ContractState> {
        fn mint(ref self: ContractState) {
            let caller = get_caller_address();

            let balance = self.erc721.balance_of(caller);
            assert(balance == 0, Errors::TOKEN_ALREADY_OWNED);

            let caller_as_felt: felt252 = caller.into();
            let token_id: u256 = caller_as_felt.into();
            self.erc721.mint(caller, caller_as_felt.into());

            let random_team = self._get_random_team(caller_as_felt);
            self.user_team.entry(caller_as_felt).write(random_team);

            self.emit(SBTMinted { user: caller, token_id, team: random_team });
        }

        fn get_user_team(self: @ContractState, user: ContractAddress) -> Team {
            let balance = self.erc721.balance_of(user);
            assert(balance != 0, Errors::NO_TOKEN_OWNED);

            let user_as_felt: felt252 = user.into();
            self.user_team.entry(user_as_felt).read()
        }

        fn has_token(self: @ContractState, user: ContractAddress) -> bool {
            let balance = self.erc721.balance_of(user);
            balance != 0
        }

        fn name(self: @ContractState) -> ByteArray {
            self.erc721.name()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc721.symbol()
        }

        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.erc721.token_uri(token_id)
        }
    }


    #[generate_trait]
    impl InternalFunctions of InternalFunctionTrait {
        // TODO: Implement Verifiable Random Function (VRF) to generate random numbers on-chain.
        fn _get_random_team(self: @ContractState, caller_as_felt: felt252) -> Team {
            let block_timestamp = get_block_timestamp();

            let team_index = block_timestamp % 3;

            match team_index {
                0 => Team::BlueFox,
                1 => Team::RedWolf,
                _ => Team::GreenApple,
            }
        }
    }

    impl ERC721HooksImpl of ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress
        ) {
            // Don't allow updates not from zero address (i.e. only mints)
            // Self-burns are disallowed by ERC721 spec
            let from = self._owner_of(token_id);
            assert(from.is_zero(), 'Transfer not allowed');
        }

        fn after_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress
        ) {}
    }
}
