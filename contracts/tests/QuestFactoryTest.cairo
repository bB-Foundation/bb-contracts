use starknet::{ClassHash, ContractAddress, contract_address_const};
use snforge_std::{
    declare, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address, spy_events,
    EventSpy, EventSpyTrait, EventSpyAssertionsTrait, DeclareResultTrait
};
use bb_contracts::QuestFactory::IQuestFactoryDispatcher;
use bb_contracts::QuestFactory::IQuestFactoryDispatcherTrait;
use bb_contracts::QuestFactory::QuestFactory::{QuestCreated};
use bb_contracts::QuestFactory::QuestFactory;
use bb_contracts::Quest::IQuestDispatcher;
use bb_contracts::Quest::IQuestDispatcherTrait;
use bb_contracts::Quest::Quest;
use bb_contracts::Gem::IGemDispatcher;
use bb_contracts::Gem::IGemDispatcherTrait;


use openzeppelin_testing::{declare_class, declare_and_deploy};
use openzeppelin_testing::constants::{CALLER, OWNER, SALT};
use openzeppelin::utils::deployments::{calculate_contract_address_from_deploy_syscall};
use openzeppelin::utils::serde::SerializedAppend;

use core::hash::{HashStateTrait, HashStateExTrait};
use core::poseidon::PoseidonTrait;

fn QUEST_CLASS_HASH() -> ClassHash {
    declare_class("Quest").class_hash
}

fn GEM_ADDRESS() -> ContractAddress {
    contract_address_const::<'GEM_ADDRESS'>()
}

fn SBT_ADDRESS() -> ContractAddress {
    contract_address_const::<'SBT_ADDRESS'>()
}

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

fn deploy_sbt() -> ContractAddress {
    let contract = declare("SBT").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(OWNER());
    let base_uri: ByteArray = "https://api.example.com/sbt/";
    calldata.append_serde(base_uri);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn setup_quest_factory_with_event() -> (
    EventSpy, IQuestFactoryDispatcher, ContractAddress, ContractAddress
) {
    let loomi_address = deploy_loomi();
    let gem_address = deploy_gem(loomi_address);
    let sbt_address = deploy_sbt();

    let mut calldata = array![];
    calldata.append_serde(OWNER());
    calldata.append_serde(gem_address);
    calldata.append_serde(sbt_address);
    calldata.append_serde(QUEST_CLASS_HASH());

    let spy = spy_events();
    let quest_factory_address = declare_and_deploy("QuestFactory", calldata);

    start_cheat_caller_address(gem_address, OWNER());
    let gem_dispatcher = IGemDispatcher { contract_address: gem_address };
    gem_dispatcher.add_trusted_handler(quest_factory_address);
    stop_cheat_caller_address(gem_address);

    (
        spy,
        IQuestFactoryDispatcher { contract_address: quest_factory_address },
        gem_address,
        sbt_address
    )
}

fn setup_quest_factory() -> (EventSpy, IQuestFactoryDispatcher, ContractAddress, ContractAddress) {
    let (mut spy, quest_factory, gem_address, sbt_address) = setup_quest_factory_with_event();

    // Drop all events
    let events = spy.get_events().events;
    spy._event_offset += events.len();

    (spy, quest_factory, gem_address, sbt_address)
}

#[test]
fn test_constructor() {
    let (_, quest_factory, gem_contract, sbt_contract) = setup_quest_factory_with_event();

    assert_eq!(quest_factory.gem_contract(), gem_contract);
    assert_eq!(quest_factory.sbt_contract(), sbt_contract);
    assert_eq!(quest_factory.quest_class_hash(), QUEST_CLASS_HASH());
}

#[test]
fn test_create_quest() {
    let (mut spy, quest_factory, gem_contract, sbt_contract) = setup_quest_factory_with_event();
    let owner = OWNER();

    // Deploy args
    let salt = SALT;
    let hashed_salt = PoseidonTrait::new().update_with(owner).update_with(salt).finalize();
    let mut quest_calldata = array![];
    quest_calldata.append_serde(OWNER());
    quest_calldata.append_serde(gem_contract);
    quest_calldata.append_serde(sbt_contract);
    quest_calldata.append_serde(QuestFactory::QuestType::SportsFitness);
    let quest_class_hash = quest_factory.quest_class_hash();

    start_cheat_caller_address(quest_factory.contract_address, owner);

    // Check address
    let expected_address = calculate_contract_address_from_deploy_syscall(
        hashed_salt, quest_class_hash, quest_calldata.span(), quest_factory.contract_address
    );

    let deployed_address = quest_factory.create_quest(QuestFactory::QuestType::SportsFitness, salt);

    assert_eq!(expected_address, deployed_address);

    // Сheck quest count
    let quest_count = quest_factory.quest_count();
    assert_eq!(quest_count, 1);

    // Сheck deploy event
    let expected_event = QuestFactory::Event::QuestCreated(
        QuestCreated {
            quest_address: deployed_address, quest_type: QuestFactory::QuestType::SportsFitness
        }
    );
    spy.assert_emitted(@array![(quest_factory.contract_address, expected_event)]);

    // Check deployment
    let quest = IQuestDispatcher { contract_address: deployed_address };
    let quest_status = quest.quest_status();
    assert_eq!(quest_status, Quest::QuestStatus::Pending);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_create_quest_not_owner() {
    let (_, quest_factory, _, _) = setup_quest_factory_with_event();
    let caller = CALLER();

    start_cheat_caller_address(quest_factory.contract_address, caller);
    quest_factory.create_quest(QuestFactory::QuestType::SportsFitness, SALT);
}

#[test]
fn test_quest_class_hash() {
    let (_, quest_factory, _, _) = setup_quest_factory();

    assert_eq!(quest_factory.quest_class_hash(), QUEST_CLASS_HASH());
}

#[test]
fn test_gem_contract() {
    let (_, quest_factory, gem_address, _) = setup_quest_factory();

    assert_eq!(quest_factory.gem_contract(), gem_address);
}

#[test]
fn test_sbt_contract() {
    let (_, quest_factory, _, sbt_contract) = setup_quest_factory();

    assert_eq!(quest_factory.sbt_contract(), sbt_contract);
}

#[test]
fn test_quest_count() {
    let (_, quest_factory, _, _) = setup_quest_factory();

    assert_eq!(quest_factory.quest_count(), 0);
}
