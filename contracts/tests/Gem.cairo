use starknet::{ContractAddress, contract_address_const};
use snforge_std::{
    declare, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address, spy_events,
    EventSpy, EventSpyAssertionsTrait, DeclareResultTrait
};
use bb_contracts::Quest::Quest;
use bb_contracts::Gem::IGemDispatcher;
use bb_contracts::Gem::IGemDispatcherTrait;
use bb_contracts::Gem::Gem::{
    GemColor, GemMinted, GemsSwaped, TrustedHandlerAdded, MinterApproved, TradeSuccessed
};
use bb_contracts::Gem::Gem;

use bb_contracts::Loomi::ILoomiDispatcher;
use bb_contracts::Loomi::ILoomiDispatcherTrait;

use openzeppelin_testing::{declare_and_deploy};
use openzeppelin_testing::constants::{OWNER};
use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_token::erc721::interface::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};

fn USER() -> ContractAddress {
    contract_address_const::<'USER'>()
}

fn USER2() -> ContractAddress {
    contract_address_const::<'USER2'>()
}

fn SBT() -> ContractAddress {
    contract_address_const::<'SBT'>()
}

// Token IDs
const TOKEN_1: u256 = 1;
const TOKEN_2: u256 = 2;
const TOKEN_3: u256 = 3;
const TOKEN_4: u256 = 4;
const TOKEN_5: u256 = 5;

const TOKENS_LEN: u256 = 5;

fn deploy_gem(loomi_address: ContractAddress) -> ContractAddress {
    let contract = declare("Gem").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(OWNER());
    calldata.append_serde(loomi_address);
    let base_uri: ByteArray = "https://api.example.com/gem/";
    calldata.append_serde(base_uri);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn deploy_loomi() -> ContractAddress {
    let contract = declare("Loomi").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(OWNER());
    let base_uri: ByteArray = "https://api.example.com/loomi/";
    calldata.append_serde(base_uri);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn deploy_quest(gem_address: ContractAddress) -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(OWNER());
    calldata.append_serde(gem_address);
    calldata.append_serde(SBT());
    calldata.append_serde(Quest::QuestType::SportsFitness);

    spy_events();
    let quest_address = declare_and_deploy("Quest", calldata);

    start_cheat_caller_address(gem_address, OWNER());
    let gem_dispatcher = IGemDispatcher { contract_address: gem_address };
    gem_dispatcher.approve_minter(quest_address);

    quest_address
}

fn setup_gem_with_event() -> (
    EventSpy, IGemDispatcher, ILoomiDispatcher, ContractAddress, ContractAddress
) {
    let loomi_address = deploy_loomi();
    let gem_address = deploy_gem(loomi_address);
    let gem_contract = IGemDispatcher { contract_address: gem_address };

    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: gem_address };
    start_cheat_caller_address(gem_address, USER());
    gem_contract.approve_transfer();

    start_cheat_caller_address(gem_address, USER2());
    gem_contract.approve_transfer();
    stop_cheat_caller_address(gem_address);

    let spy = spy_events();
    (
        spy,
        IGemDispatcher { contract_address: gem_address },
        ILoomiDispatcher { contract_address: loomi_address },
        gem_address,
        loomi_address
    )
}

#[test]
fn test_deployment() {
    let loomi_address = deploy_loomi();
    let gem_address = deploy_gem(loomi_address);
    let dispatcher = ERC721ABIDispatcher { contract_address: gem_address };

    assert(dispatcher.name() == "Gem", 'Wrong name');
    assert(dispatcher.symbol() == "GEM", 'Wrong symbol');
}

#[test]
fn test_minting() {
    let (mut spy, gem_dispatcher, _, gem_address, _) = setup_gem_with_event();
    let quest_address = deploy_quest(gem_address);

    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: gem_address };

    // Start acting as quest contract
    start_cheat_caller_address(gem_address, quest_address);

    // Mint GEM - token ID will be number as u256 and color GemColor::Blue
    gem_dispatcher.mint(USER(), 0);

    // Сheck GEM minted event
    let expected_event = Gem::Event::GemMinted(GemMinted { user: USER(), color: GemColor::Blue });
    spy.assert_emitted(@array![(gem_address, expected_event)]);

    // Verify ownership
    let token_id: u256 = 1;
    assert(erc721_dispatcher.owner_of(token_id) == USER(), 'Wrong token owner');
    assert(erc721_dispatcher.balance_of(USER()) == 1, 'Wrong balance');
}

#[test]
fn test_trade() {
    let (mut spy, gem_dispatcher, _, gem_address, _) = setup_gem_with_event();
    let quest_address = deploy_quest(gem_address);

    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: gem_address };

    // Start acting as quest contract
    start_cheat_caller_address(gem_address, quest_address);

    // Mint GEM - token ID will be number as u256 and color GemColor::Blue
    gem_dispatcher.mint(USER(), 0);
    gem_dispatcher.mint(USER(), 1);
    gem_dispatcher.mint(USER(), 2);

    gem_dispatcher.mint(USER2(), 3);
    gem_dispatcher.mint(USER2(), 4);

    // Start acting as owner
    start_cheat_caller_address(gem_address, OWNER());

    // Trade
    let initiator_tokens = array![TOKEN_1, TOKEN_2];
    let counterparty_tokens = array![TOKEN_4, TOKEN_5];

    gem_dispatcher.trade(USER(), USER2(), initiator_tokens, counterparty_tokens);

    // Сheck trade successed event
    let expected_event = Gem::Event::TradeSuccessed(
        TradeSuccessed { trade_id: 1, initiator: USER(), counterparty: USER2(), }
    );
    spy.assert_emitted(@array![(gem_address, expected_event)]);

    // Verify ownership
    assert(erc721_dispatcher.owner_of(TOKEN_4) == USER(), 'Wrong token owner');
    assert(erc721_dispatcher.owner_of(TOKEN_5) == USER(), 'Wrong token owner');
    assert(erc721_dispatcher.owner_of(TOKEN_1) == USER2(), 'Wrong token owner');
    assert(erc721_dispatcher.owner_of(TOKEN_2) == USER2(), 'Wrong token owner');
}

#[test]
#[should_panic(expected: ('No token owned by user',))]
fn test_trade_token_not_owned() {
    let (mut spy, gem_dispatcher, _, gem_address, _) = setup_gem_with_event();
    let quest_address = deploy_quest(gem_address);

    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: gem_address };

    // Start acting as quest contract
    start_cheat_caller_address(gem_address, quest_address);

    // Mint GEM - token ID will be number as u256 and color GemColor::Blue
    gem_dispatcher.mint(USER(), 0);
    gem_dispatcher.mint(USER(), 1);
    gem_dispatcher.mint(USER(), 2);

    gem_dispatcher.mint(USER2(), 3);
    gem_dispatcher.mint(USER2(), 4);

    // Start acting as owner
    start_cheat_caller_address(gem_address, OWNER());

    // Trade
    let initiator_tokens = array![TOKEN_1, TOKEN_2];
    let counterparty_tokens = array![TOKEN_3, TOKEN_5];

    gem_dispatcher.trade(USER(), USER2(), initiator_tokens, counterparty_tokens);

    // Verify ownership
    assert(erc721_dispatcher.owner_of(TOKEN_1) == USER(), 'Wrong token owner');
    assert(erc721_dispatcher.owner_of(TOKEN_2) == USER(), 'Wrong token owner');
    assert(erc721_dispatcher.owner_of(TOKEN_4) == USER2(), 'Wrong token owner');
    assert(erc721_dispatcher.owner_of(TOKEN_5) == USER2(), 'Wrong token owner');
}

#[test]
#[should_panic(expected: ('Invalid number of tokens',))]
fn test_trade_invalid_amount_tokens() {
    let (_, gem_dispatcher, _, gem_address, _) = setup_gem_with_event();
    // Start acting as owner
    start_cheat_caller_address(gem_address, OWNER());

    // Trade
    let initiator_tokens = array![TOKEN_1, TOKEN_2, TOKEN_3];
    let counterparty_tokens = array![TOKEN_4, TOKEN_5];

    gem_dispatcher.trade(USER(), USER2(), initiator_tokens, counterparty_tokens);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_trade_not_owner() {
    let (_, gem_dispatcher, _, gem_address, _) = setup_gem_with_event();
    // Start acting as owner
    start_cheat_caller_address(gem_address, USER());

    // Trade
    let initiator_tokens = array![TOKEN_1, TOKEN_2, TOKEN_3];
    let counterparty_tokens = array![TOKEN_4, TOKEN_5];

    gem_dispatcher.trade(USER(), USER2(), initiator_tokens, counterparty_tokens);
}

// Check TOKEN_NOT_OWNED

#[test]
#[should_panic(expected: ('Unauthorized minting attempt',))]
fn test_minting_unauthorized_minting() {
    let loomi_address = deploy_loomi();
    let gem_address = deploy_gem(loomi_address);

    let gem_dispatcher = IGemDispatcher { contract_address: gem_address };

    // Start acting as USER
    start_cheat_caller_address(gem_address, USER());

    // Mint GEM - token ID will be number as u256 and color GemColor::Blue
    gem_dispatcher.mint(USER(), 0);
}

#[test]
fn test_swap() {
    let (mut spy, gem_dispatcher, loomi_dispatcher, gem_address, loomi_address) =
        setup_gem_with_event();
    let quest_address = deploy_quest(gem_address);

    start_cheat_caller_address(loomi_address, OWNER());
    loomi_dispatcher.approve_minter(gem_address);

    let gem_erc721_dispatcher = ERC721ABIDispatcher { contract_address: gem_address };
    let loomi_erc721_dispatcher = ERC721ABIDispatcher { contract_address: loomi_address };

    // Start acting as quest contract
    start_cheat_caller_address(gem_address, quest_address);

    // Mint GEM tokens with 5 different colors
    gem_dispatcher.mint(USER(), 0);
    gem_dispatcher.mint(USER(), 1);
    gem_dispatcher.mint(USER(), 2);
    gem_dispatcher.mint(USER(), 3);
    gem_dispatcher.mint(USER(), 4);

    assert(gem_erc721_dispatcher.balance_of(USER()) == 5, 'Wrong balance');

    start_cheat_caller_address(gem_address, USER());
    start_cheat_caller_address(loomi_address, gem_address);
    gem_dispatcher.swap(array![TOKEN_1, TOKEN_2, TOKEN_3, TOKEN_4, TOKEN_5]);

    assert(gem_erc721_dispatcher.balance_of(USER()) == 0, 'Wrong balance');
    assert(loomi_erc721_dispatcher.balance_of(USER()) == 1, 'Wrong balance');

    // Сheck GEM swaped event
    let expected_event = Gem::Event::GemsSwaped(GemsSwaped { user: USER() });
    spy.assert_emitted(@array![(gem_address, expected_event)]);
}

#[test]
#[should_panic(expected: ('No token owned by user',))]
fn test_swap_no_token_owned() {
    let (_, gem_dispatcher, loomi_dispatcher, gem_address, loomi_address) = setup_gem_with_event();
    let quest_address = deploy_quest(gem_address);

    start_cheat_caller_address(loomi_address, OWNER());
    loomi_dispatcher.approve_minter(gem_address);

    // Start acting as quest contract
    start_cheat_caller_address(gem_address, quest_address);

    // Mint GEM tokens with 5 different colors
    gem_dispatcher.mint(USER2(), 0);

    start_cheat_caller_address(gem_address, USER());
    gem_dispatcher.swap(array![TOKEN_1, TOKEN_2, TOKEN_3, TOKEN_4, TOKEN_5]);
}

#[test]
#[should_panic(expected: ('Invalid number of tokens',))]
fn test_swap_invalid_amount_tokens() {
    let (_, gem_dispatcher, _, gem_address, _) = setup_gem_with_event();

    start_cheat_caller_address(gem_address, USER());
    gem_dispatcher.swap(array![TOKEN_1]);
}

#[test]
#[should_panic(expected: ('Duplicate gem colors',))]
fn test_swap_invalid_gem_color() {
    let (_, gem_dispatcher, loomi_dispatcher, gem_address, loomi_address) = setup_gem_with_event();
    let quest_address = deploy_quest(gem_address);

    start_cheat_caller_address(loomi_address, OWNER());
    loomi_dispatcher.approve_minter(gem_address);

    // Start acting as quest contract
    start_cheat_caller_address(gem_address, quest_address);

    // Mint GEM tokens with 5 different colors
    gem_dispatcher.mint(USER(), 0);
    gem_dispatcher.mint(USER(), 0);
    gem_dispatcher.mint(USER(), 2);
    gem_dispatcher.mint(USER(), 3);
    gem_dispatcher.mint(USER(), 4);

    start_cheat_caller_address(gem_address, USER());
    gem_dispatcher.swap(array![TOKEN_1, TOKEN_2, TOKEN_3, TOKEN_4, TOKEN_5]);
}

#[test]
fn test_get_tokens_of_owner() {
    let loomi_address = deploy_loomi();
    let gem_address = deploy_gem(loomi_address);
    let quest_address = deploy_quest(gem_address);

    let gem_dispatcher = IGemDispatcher { contract_address: gem_address };
    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: gem_address };

    // Start acting as quest contract
    start_cheat_caller_address(gem_address, quest_address);

    // Mint GEMs
    let token_id_1 = gem_dispatcher.mint(USER(), 0);
    let token_id_2 = gem_dispatcher.mint(USER2(), 0);
    let token_id_3 = gem_dispatcher.mint(USER(), 0);

    assert(token_id_1 == 1, 'Wrong token id');
    assert(token_id_2 == 2, 'Wrong token id');
    assert(token_id_3 == 3, 'Wrong token id');

    // Verify ownership
    assert(erc721_dispatcher.balance_of(USER()) == 2, 'Wrong balance');
    assert(erc721_dispatcher.balance_of(USER2()) == 1, 'Wrong balance');
    assert_eq!(gem_dispatcher.get_tokens_of_owner(USER()), array![1, 3]);
    assert_eq!(gem_dispatcher.get_tokens_of_owner(USER2()), array![2]);
}

#[test]
fn test_add_trusted_handler() {
    let (mut spy, gem_dispatcher, _, gem_address, _) = setup_gem_with_event();

    // Start acting as owner
    start_cheat_caller_address(gem_address, OWNER());

    // Add trusted handler
    gem_dispatcher.add_trusted_handler(USER());

    let expected_event = Gem::Event::TrustedHandlerAdded(
        TrustedHandlerAdded { trusted_handler: USER() }
    );
    spy.assert_emitted(@array![(gem_address, expected_event)]);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_add_trusted_handler_not_owner() {
    let loomi_address = deploy_loomi();
    let gem_address = deploy_gem(loomi_address);

    let gem_dispatcher = IGemDispatcher { contract_address: gem_address };

    // Start acting as user
    start_cheat_caller_address(gem_address, USER());

    // Add trusted handler
    gem_dispatcher.add_trusted_handler(USER2());
}

#[test]
fn test_approve_minter() {
    let (mut spy, gem_dispatcher, _, gem_address, _) = setup_gem_with_event();

    // Start acting as owner
    start_cheat_caller_address(gem_address, OWNER());

    // Add trusted handler
    gem_dispatcher.add_trusted_handler(USER());

    // Start acting as user
    start_cheat_caller_address(gem_address, USER());

    // Approve minter
    gem_dispatcher.approve_minter(USER2());

    let expected_event = Gem::Event::MinterApproved(MinterApproved { minter: USER2() });
    spy.assert_emitted(@array![(gem_address, expected_event)]);
}

#[test]
#[should_panic(expected: ('Unauthorized access attempt',))]
fn test_approve_minter_unauthorized_access() {
    let loomi_address = deploy_loomi();
    let gem_address = deploy_gem(loomi_address);

    let gem_dispatcher = IGemDispatcher { contract_address: gem_address };

    // Start acting as user
    start_cheat_caller_address(gem_address, USER());

    // Approve minter
    gem_dispatcher.approve_minter(USER2());
}

#[test]
#[should_panic(expected: ('Transfer not allowed',))]
fn test_cant_transfer_gem() {
    let (_, gem_dispatcher, _, gem_address, _) = setup_gem_with_event();
    let quest_address = deploy_quest(gem_address);

    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: gem_address };

    // Start acting as quest contract
    start_cheat_caller_address(gem_address, quest_address);

    // Mint GEM - token ID will be number as u256 and color GemColor::Blue
    gem_dispatcher.mint(USER(), 0);

    // Try to transfer to USER2
    start_cheat_caller_address(gem_address, USER());
    let token_id: u256 = 1;
    erc721_dispatcher.transfer_from(USER(), USER2(), token_id);
}

#[test]
fn test_name() {
    let loomi_address = deploy_loomi();
    let gem_address = deploy_gem(loomi_address);
    let gem_dispatcher = ERC721ABIDispatcher { contract_address: gem_address };

    assert_eq!(gem_dispatcher.name(), "Gem");
}

#[test]
fn test_symbol() {
    let loomi_address = deploy_loomi();
    let gem_address = deploy_gem(loomi_address);
    let gem_dispatcher = ERC721ABIDispatcher { contract_address: gem_address };

    assert_eq!(gem_dispatcher.symbol(), "GEM");
}

#[test]
fn test_token_uri() {
    let loomi_address = deploy_loomi();
    let gem_address = deploy_gem(loomi_address);
    let quest_address = deploy_quest(gem_address);

    let gem_dispatcher = IGemDispatcher { contract_address: gem_address };

    // Start acting as quest contract
    start_cheat_caller_address(gem_address, quest_address);

    // Mint GEM - token ID will be number as u256 and color GemColor::Blue
    gem_dispatcher.mint(USER(), 0);

    let token_id: u256 = 1;
    assert_eq!(gem_dispatcher.token_uri(token_id), "https://api.example.com/gem/1");
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID',))]
fn test_token_uri_nonexistent() {
    let loomi_address = deploy_loomi();
    let gem_address = deploy_gem(loomi_address);
    let quest_address = deploy_quest(gem_address);

    let gem_dispatcher = IGemDispatcher { contract_address: gem_address };

    // Start acting as quest contract
    start_cheat_caller_address(gem_address, quest_address);

    // Mint GEM - token ID will be number as u256 and color GemColor::Blue
    gem_dispatcher.mint(USER(), 0);

    let invalid_token_id: u256 = 99999;

    // Try to get URI for non-existent token
    gem_dispatcher.token_uri(invalid_token_id);
}
