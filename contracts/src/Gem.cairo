use starknet::{ContractAddress};

#[starknet::interface]
pub trait IGem<TContractState> {
    fn mint(ref self: TContractState, user: ContractAddress, color: u8) -> u256;
    fn approve_minter(ref self: TContractState, minter: ContractAddress);
    fn add_trusted_handler(ref self: TContractState, trusted_handler: ContractAddress);
    fn swap(ref self: TContractState, token_ids: Array<u256>) -> u256;
    fn get_tokens_of_owner(ref self: TContractState, user: ContractAddress) -> Array<u256>;
    fn trade(
        ref self: TContractState,
        initiator: ContractAddress,
        counterparty: ContractAddress,
        initiator_tokens: Array<u256>,
        counterparty_tokens: Array<u256>
    ) -> u256;
    // ERC721 overrides
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn token_uri(self: @TContractState, token_id: u256) -> ByteArray;
}

#[starknet::contract]
pub mod Gem {
    use crate::Loomi::{ILoomiDispatcher, ILoomiDispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin_token::erc721::extensions::erc721_enumerable::ERC721EnumerableComponent;
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::ERC721Component::ERC721HooksTrait;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::{get_caller_address, ContractAddress};
    use starknet::storage::{Map, StoragePathEntry};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use core::num::traits::Zero;
    use super::{IGem};

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
        GemMinted: GemMinted,
        GemsSwaped: GemsSwaped,
        MinterApproved: MinterApproved,
        TrustedHandlerAdded: TrustedHandlerAdded,
        TradeSuccessed: TradeSuccessed,
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
    pub struct GemMinted {
        pub user: ContractAddress,
        pub color: GemColor
    }
    #[derive(Drop, starknet::Event)]
    pub struct MinterApproved {
        pub minter: ContractAddress
    }
    #[derive(Drop, starknet::Event)]
    pub struct TrustedHandlerAdded {
        pub trusted_handler: ContractAddress
    }
    #[derive(Drop, starknet::Event)]
    pub struct GemsSwaped {
        pub user: ContractAddress
    }
    #[derive(Drop, starknet::Event)]
    pub struct TradeSuccessed {
        pub trade_id: u256,
        pub initiator: ContractAddress,
        pub counterparty: ContractAddress,
    }

    #[storage]
    struct Storage {
        loomi_address: ContractAddress,
        gems: Map<u256, GemAttributes>, // token_id -> gem_attributes
        last_token_id: u256,
        approved_minters: Map<ContractAddress, bool>,
        trusted_handlers: Map<ContractAddress, bool>,
        last_trade_id: u256,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        pub erc721_enumerable: ERC721EnumerableComponent::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[derive(Debug, Copy, Drop, Serde, PartialEq, starknet::Store)]
    pub enum GemColor {
        Blue,
        Yellow,
        Pink,
        Purple,
        Green
    }

    #[derive(Debug, Drop, Serde, starknet::Store)]
    pub struct GemAttributes {
        color: GemColor,
        original_owner: ContractAddress,
        current_owner: ContractAddress
    }

    pub mod Errors {
        pub const INVALID_ADDRESS: felt252 = 'Invalid address';
        pub const INVALID_CLASS_HASH: felt252 = 'Invalid class hash';
        pub const UNAUTHORIZED_MINTING: felt252 = 'Unauthorized minting attempt';
        pub const UNAUTHORIZED_ACCESS: felt252 = 'Unauthorized access attempt';
        pub const TRANSFER_NOT_ALLOWED: felt252 = 'Transfer not allowed';
        pub const INVALID_AMOUNT_TOKENS: felt252 = 'Invalid number of tokens';
        pub const DUPLICATE_GEM_COLORS: felt252 = 'Duplicate gem colors';
        pub const TOKEN_NOT_OWNED: felt252 = 'No token owned by user';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        loomi_address: ContractAddress,
        base_uri: ByteArray
    ) {
        self.erc721.initializer("Gem", "GEM", base_uri);
        self.erc721_enumerable.initializer();
        self.ownable.initializer(owner);
        self.loomi_address.write(loomi_address);
        self.trusted_handlers.entry(owner).write(true);
    }

    #[abi(embed_v0)]
    impl GemImpl of IGem<ContractState> {
        fn mint(ref self: ContractState, user: ContractAddress, color: u8) -> u256 {
            let minter = get_caller_address();
            assert(
                self.approved_minters.entry(minter).read() == true, Errors::UNAUTHORIZED_MINTING
            );

            // Mint new token
            let new_token_id = self.last_token_id.read() + 1;
            self.last_token_id.write(new_token_id);
            self.erc721.mint(user, new_token_id);

            // TODO: Remove current_owner
            let gem_color = self._u8_as_color(color);
            let gem_attributes = GemAttributes {
                color: gem_color, original_owner: user, current_owner: user
            };

            self.gems.entry(new_token_id).write(gem_attributes);
            self.emit(GemMinted { user, color: gem_color });

            new_token_id
        }

        fn approve_minter(ref self: ContractState, minter: ContractAddress) {
            let caller = get_caller_address();
            assert(self.trusted_handlers.entry(caller).read() == true, Errors::UNAUTHORIZED_ACCESS);

            self.approved_minters.entry(minter).write(true);
            self.emit(MinterApproved { minter });
        }

        fn add_trusted_handler(ref self: ContractState, trusted_handler: ContractAddress) {
            self.ownable.assert_only_owner();

            self.trusted_handlers.entry(trusted_handler).write(true);

            self.emit(TrustedHandlerAdded { trusted_handler });
        }


        fn trade(
            ref self: ContractState,
            initiator: ContractAddress,
            counterparty: ContractAddress,
            initiator_tokens: Array<u256>,
            counterparty_tokens: Array<u256>
        ) -> u256 {
            self.ownable.assert_only_owner();

            assert(
                initiator_tokens.len() == counterparty_tokens.len(), Errors::INVALID_AMOUNT_TOKENS
            );

            // Pre-verify ownership of all tokens
            for i in 0
                ..initiator_tokens
                    .len() {
                        let token_id = *initiator_tokens.at(i);
                        assert(
                            self.erc721.owner_of(token_id) == initiator, Errors::TOKEN_NOT_OWNED
                        );
                    };

            for i in 0
                ..counterparty_tokens
                    .len() {
                        let token_id = *counterparty_tokens.at(i);
                        assert(
                            self.erc721.owner_of(token_id) == counterparty, Errors::TOKEN_NOT_OWNED
                        );
                    };

            let new_trade_id = self.last_trade_id.read() + 1;
            self.last_trade_id.write(new_trade_id);

            // Transfer initiator's tokens to counterparty
            for i in 0
                ..initiator_tokens
                    .len() {
                        let token_id = *initiator_tokens.at(i);
                        self.erc721.transfer_from(initiator, counterparty, token_id);
                    };

            // Transfer counterparty's tokens to initiator
            for i in 0
                ..counterparty_tokens
                    .len() {
                        let token_id = *counterparty_tokens.at(i);
                        self.erc721.transfer_from(counterparty, initiator, token_id);
                    };

            // Emit an event for trade initiation
            self.emit(TradeSuccessed { trade_id: new_trade_id, initiator, counterparty, });

            new_trade_id
        }


        fn swap(ref self: ContractState, token_ids: Array<u256>) -> u256 {
            let caller = get_caller_address();

            assert(token_ids.len() == 5, Errors::INVALID_AMOUNT_TOKENS);

            let mut colors = array![];
            for token_id in token_ids {
                let owner = self.erc721.owner_of(token_id);
                assert(owner == caller, Errors::TOKEN_NOT_OWNED);

                let gem_attributes = self.gems.entry(token_id).read();

                // Ensure the color is unique among provided tokens.
                for i in 0
                    ..colors
                        .len() {
                            assert(
                                *colors.at(i) != gem_attributes.color, Errors::DUPLICATE_GEM_COLORS
                            );
                        };

                colors.append(gem_attributes.color);

                self.erc721.burn(token_id);
            };

            let loomi_dispatcher = ILoomiDispatcher { contract_address: self.loomi_address.read() };
            let new_token_id = loomi_dispatcher.mint(caller);

            self.emit(GemsSwaped { user: caller });

            new_token_id
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

    #[generate_trait]
    impl InternalFunctions of InternalFunctionTrait {
        fn _u8_as_color(self: @ContractState, gem_color: u8) -> GemColor {
            match gem_color {
                0 => GemColor::Blue,
                1 => GemColor::Yellow,
                2 => GemColor::Pink,
                3 => GemColor::Purple,
                4 => GemColor::Green,
                _ => GemColor::Blue,
            }
        }

        fn _color_as_u8(self: @ContractState, gem_color: GemColor) -> u8 {
            match gem_color {
                GemColor::Blue => 0,
                GemColor::Yellow => 1,
                GemColor::Pink => 2,
                GemColor::Purple => 3,
                GemColor::Green => 4,
                _ => 0,
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
            let contract_state = self.get_contract();
            let owner = contract_state.ownable.Ownable_owner.read();
            let caller = get_caller_address();
            if caller != owner {
                // Don't allow updates not from zero address (i.e. only mints and burn)
                let from = self._owner_of(token_id);

                let mut contract_state = self.get_contract_mut();
                contract_state.erc721_enumerable.before_update(to, token_id);

                if to.is_zero() {
                    return;
                } else if from.is_zero() {
                    return;
                }

                assert(false, Errors::TRANSFER_NOT_ALLOWED);
            }
        }

        fn after_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress
        ) {}
    }
}
