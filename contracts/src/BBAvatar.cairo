use starknet::{ContractAddress};

#[derive(Drop, Serde)]
pub struct AccessoryInfo {
    pub affiliate_id: felt252,
    pub accessory_id: felt252,
    pub is_on: bool,
}

#[starknet::interface]
pub trait IBBAvatar<TContractState> {
    // mint your own avatar
    fn mint(ref self: TContractState);
    fn update_accessories(ref self: TContractState, accessory_list: Span<AccessoryInfo>);
    fn register_affiliate(
        ref self: TContractState, affiliate_id: felt252, contract_address: ContractAddress
    );
    fn register_accessory(ref self: TContractState, affiliate_id: felt252, accessory_id: felt252);
    fn has_accessory(
        self: @TContractState, token_id: u256, affiliate_id: felt252, accessory_id: felt252
    ) -> bool;
    fn get_accessories_for_affiliate(self: @TContractState, affiliate_id: felt252) -> Span<felt252>;
    fn get_affiliates(self: @TContractState) -> Span<felt252>;
    // ERC721 overrides
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn token_uri(self: @TContractState, token_id: u256) -> ByteArray;
    fn tokenUri(self: @TContractState, token_id: u256) -> ByteArray;
}

#[starknet::contract]
mod BBAvatar {
    use core::num::traits::Zero;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc721::ERC721Component::ERC721HooksTrait;
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::interface::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
    use starknet::storage::{Map, StoragePathEntry, Vec, VecTrait, MutableVecTrait};
    use starknet::{get_caller_address, ContractAddress};
    use super::{IBBAvatar, AccessoryInfo};

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
        // token_id -> affiliate_id -> accessory_id -> is_on
        item_accessories: Map<u256, Map<felt252, Map<felt252, bool>>>,
        // affiliate_id -> contract_address
        affiliate_contracts: Map<felt252, ContractAddress>,
        all_affiliates_list: Vec<felt252>,
        all_accessories_list: Map<felt252, Vec<felt252>>,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        accessory_info: AccessoryInfo,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, base_uri: ByteArray) {
        self.erc721.initializer("BBAvatar", "BBAV", base_uri);
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl BBAvatarImpl of IBBAvatar<ContractState> {
        fn mint(ref self: ContractState) {
            let caller = get_caller_address();
            // check if the caller already has a token
            let balance = self.erc721.balance_of(caller);
            assert(balance == 0, 'Caller already has a token');

            // mint a new token (the token id is the caller's address)
            let caller_as_felt: felt252 = caller.into();
            self.erc721.mint(caller, caller_as_felt.into());
        }

        fn update_accessories(ref self: ContractState, accessory_list: Span<AccessoryInfo>) {
            // get the token of the caller
            let caller = get_caller_address();
            let caller_as_felt: felt252 = caller.into();
            let token_id = caller_as_felt.into();

            // check if the caller has the token, mint otherwise
            let balance = self.erc721.balance_of(caller);
            if balance == 0 {
                self.erc721.mint(caller, caller_as_felt.into());
            }

            // Oh that will take a lot of gas
            for accessory in accessory_list {
                // for each accessory in the list, load the key contract
                let key_contract_address = self
                    .affiliate_contracts
                    .entry(*accessory.affiliate_id)
                    .read();
                assert(!key_contract_address.is_zero(), 'Affiliate key not registered');
                // check if the caller has the key
                let key_contract = ERC721ABIDispatcher { contract_address: key_contract_address, };
                let _has_key = key_contract.balance_of(caller) > 0;
                // get the current state of the accessory
                let current_state = self
                    .item_accessories
                    .entry(token_id)
                    .entry(*accessory.affiliate_id)
                    .entry(*accessory.accessory_id)
                    .read();
                // if they don't have accessory on, and they want to turn it on, check if they have
                // the key
                if !current_state
                    && *accessory.is_on { // TODO: enable this once we have everything integrated
                // assert(has_key, 'Caller does not have the key');
                }
                // write the new state
                self
                    .item_accessories
                    .entry(token_id)
                    .entry(*accessory.affiliate_id)
                    .entry(*accessory.accessory_id)
                    .write(*accessory.is_on);
            }
        }
        fn register_affiliate(
            ref self: ContractState, affiliate_id: felt252, contract_address: ContractAddress
        ) {
            self.ownable.assert_only_owner();
            self.affiliate_contracts.entry(affiliate_id).write(contract_address);
            self.all_affiliates_list.append().write(affiliate_id);
        }
        // Registers an accessory for an affiliate
        // Now serves purely for enumeration, but could be used for accessory validation in the
        // future
        fn register_accessory(
            ref self: ContractState, affiliate_id: felt252, accessory_id: felt252
        ) {
            self.ownable.assert_only_owner();
            self.all_accessories_list.entry(affiliate_id).append().write(accessory_id);
        }
        fn has_accessory(
            self: @ContractState, token_id: u256, affiliate_id: felt252, accessory_id: felt252
        ) -> bool {
            self.item_accessories.entry(token_id).entry(affiliate_id).entry(accessory_id).read()
        }
        fn get_accessories_for_affiliate(
            self: @ContractState, affiliate_id: felt252
        ) -> Span<felt252> {
            let mut accessories_arr = array![];
            let registered_accessories = self.all_accessories_list.entry(affiliate_id);
            let len = registered_accessories.len();
            for i in 0..len {
                accessories_arr.append(registered_accessories.at(i).read());
            };
            accessories_arr.span()
        }
        fn get_affiliates(self: @ContractState) -> Span<felt252> {
            let mut affiliates_arr = array![];
            let len = self.all_affiliates_list.len();
            for i in 0..len {
                affiliates_arr.append(self.all_affiliates_list.at(i).read());
            };
            affiliates_arr.span()
        }
        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.tokenUri(token_id)
        }
        fn name(self: @ContractState) -> ByteArray {
            self.erc721.name()
        }
        fn symbol(self: @ContractState) -> ByteArray {
            self.erc721.symbol()
        }
        fn tokenUri(self: @ContractState, token_id: u256) -> ByteArray {
            // Check if token exists (done by ERC721)
            let _ = self.erc721.owner_of(token_id);

            let mut token_uri = self.erc721._base_uri();

            // Iterate over all accessories and compose the URL from weared ones:
            // http://base_uri?bored_apes=hat,t-shirt&oxford=hat

            let mut first_affiliate = true;
            for i in 0
                ..self
                    .all_affiliates_list
                    .len() {
                        let affiliate_id = self.all_affiliates_list.at(i).read();
                        let accessories = self.all_accessories_list.entry(affiliate_id);
                        let mut aff_used = false;
                        for j in 0
                            ..accessories
                                .len() {
                                    let accessory_id = accessories.at(j).read();
                                    let is_on = self
                                        .item_accessories
                                        .entry(token_id)
                                        .entry(affiliate_id)
                                        .entry(accessory_id)
                                        .read();
                                    if is_on {
                                        if !aff_used {
                                            if first_affiliate {
                                                token_uri =
                                                    format!("{}?{}=", token_uri, affiliate_id);
                                                first_affiliate = false;
                                            } else {
                                                token_uri =
                                                    format!("{}&{}=", token_uri, affiliate_id);
                                            }
                                            aff_used = true;
                                        } else {
                                            token_uri = format!("{},", token_uri);
                                        }
                                        token_uri = format!("{}{}", token_uri, accessory_id);
                                    }
                                }
                    };

            token_uri
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
