use starknet::{ContractAddress};

#[starknet::interface]
pub trait ILoomi<TContractState> {
    fn mint(ref self: TContractState, user: ContractAddress) -> u256;
    fn approve_minter(ref self: TContractState, minter: ContractAddress);
    fn get_tokens_of_owner(ref self: TContractState, user: ContractAddress) -> Array<u256>;
    // ERC721 overrides
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn token_uri(self: @TContractState, token_id: u256) -> ByteArray;
}

#[starknet::contract]
pub mod Loomi {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin_token::erc721::extensions::erc721_enumerable::ERC721EnumerableComponent;
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::ERC721Component::ERC721HooksTrait;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::{get_caller_address, ContractAddress};
    use starknet::storage::{Map, StoragePathEntry};
    use core::num::traits::Zero;
    use super::{ILoomi};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(
        path: ERC721EnumerableComponent, storage: erc721_enumerable, event: ERC721EnumerableEvent
    );
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721EnumerableImpl =
        ERC721EnumerableComponent::ERC721EnumerableImpl<ContractState>;
    impl ERC721EnumerableInternalImpl = ERC721EnumerableComponent::InternalImpl<ContractState>;

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
        LoomiMinted: LoomiMinted,
        MinterApproved: MinterApproved,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        ERC721EnumerableEvent: ERC721EnumerableComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }
    #[derive(Drop, starknet::Event)]
    pub struct LoomiMinted {
        pub user: ContractAddress
    }
    #[derive(Drop, starknet::Event)]
    pub struct MinterApproved {
        pub minter: ContractAddress
    }

    #[storage]
    struct Storage {
        approved_minters: Map<ContractAddress, bool>,
        last_token_id: u256,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        pub erc721_enumerable: ERC721EnumerableComponent::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    pub mod Errors {
        pub const INVALID_ADDRESS: felt252 = 'Invalid address';
        pub const INVALID_CLASS_HASH: felt252 = 'Invalid class hash';
        pub const UNAUTHORIZED_MINTING: felt252 = 'Unauthorized minting attempt';
        pub const UNAUTHORIZED_ACCESS: felt252 = 'Unauthorized access attempt';
        pub const TRANSFER_NOT_ALLOWED: felt252 = 'Transfer not allowed';
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, base_uri: ByteArray) {
        self.erc721.initializer("Loomi", "LOOMI", base_uri);
        self.erc721_enumerable.initializer();
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl LoomiImpl of ILoomi<ContractState> {
        fn mint(ref self: ContractState, user: ContractAddress) -> u256 {
            let minter = get_caller_address();
            assert(
                self.approved_minters.entry(minter).read() == true, Errors::UNAUTHORIZED_MINTING
            );

            // Increment counter
            let current_token_id = self.last_token_id.read();
            let next_token_id = current_token_id + 1;

            // Mint new token
            self.erc721.mint(user, next_token_id.into());
            self.last_token_id.write(next_token_id);

            self.emit(LoomiMinted { user });

            next_token_id
        }

        fn approve_minter(ref self: ContractState, minter: ContractAddress) {
            self.ownable.assert_only_owner();

            self.approved_minters.entry(minter).write(true);
            self.emit(MinterApproved { minter });
        }

        fn get_tokens_of_owner(ref self: ContractState, user: ContractAddress) -> Array<u256> {
            let balance = self.erc721.balance_of(user);

            let mut tokens_of_owner = array![];

            if balance.is_zero() {
                return tokens_of_owner;
            }

            for i in 0
                ..balance {
                    let token_id = self.erc721_enumerable.token_of_owner_by_index(user, i);
                    tokens_of_owner.append(token_id);
                };

            tokens_of_owner
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

    impl ERC721HooksImpl of ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress
        ) {
            // Don't allow updates not from zero address (i.e. only mints)
            let from = self._owner_of(token_id);
            assert(from.is_zero(), Errors::TRANSFER_NOT_ALLOWED);

            let mut contract_state = self.get_contract_mut();
            contract_state.erc721_enumerable.before_update(to, token_id);
        }

        fn after_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress
        ) {}
    }
}
