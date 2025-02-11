use starknet::{ContractAddress};

#[starknet::interface]
pub trait IWardrobeKey<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress);
    fn mint_signed(ref self: TContractState, to: ContractAddress, signature: Span<felt252>);
}

#[starknet::contract]
mod WardrobeKey {
    use core::num::traits::Zero;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc721::ERC721Component::ERC721HooksTrait;
    use openzeppelin_token::erc721::ERC721Component;
    use starknet::ContractAddress;
    use super::{IWardrobeKey};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[storage]
    struct Storage {
        last_token_id: u256,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, base_uri: ByteArray) {
        self.erc721.initializer("WardrobeKey", "WKEY", base_uri);
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl WardrobeKeyImpl of IWardrobeKey<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress) {
            // TODO: enable this check once we have Metamask integration
            // self.ownable.assert_only_owner();
            let new_token_id = self.last_token_id.read() + 1;
            self.last_token_id.write(new_token_id);
            self.erc721.mint(to, new_token_id);
        }

        fn mint_signed(ref self: ContractState, to: ContractAddress, signature: Span<felt252>) {
            // TODO: implement signature verification
            self.mint(to);
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
