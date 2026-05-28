// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {SaturnTimelock} from "../../contracts/common/SaturnTimelock.sol";

contract TimelockCallReceiverMock {
    event MockFunctionCalled();

    function mockFunction() external payable {
        emit MockFunctionCalled();
    }

    function mockFunctionRevertsNoReason() external pure {
        revert();
    }

    function mockFunctionThrows() external pure {
        assert(false);
    }

    function mockFunctionOutOfGas() external pure {
        while (true) {}
    }

    function mockFunctionNonPayable() external {}

    receive() external payable {}
}

contract TimelockImplementation2 {
    uint256 internal value;

    function setValue(uint256 _value) external {
        value = _value;
    }

    function getValue() external view returns (uint256) {
        return value;
    }
}

contract TimelockReentrant {
    TimelockController internal timelock;
    bytes internal data;
    bool internal enabled;
    bool internal entered;

    function enableReentrancy(TimelockController _timelock, bytes calldata _data) external {
        timelock = _timelock;
        data = _data;
        enabled = true;
        entered = false;
    }

    function disableReentrancy() external {
        enabled = false;
        entered = false;
    }

    function reenter() external {
        if (!enabled || entered) return;
        entered = true;

        (bool success, bytes memory returndata) = address(timelock).call(data);
        if (!success) {
            assembly {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }
    }
}

contract TimelockERC721Mock is ERC721 {
    constructor() ERC721("Non Fungible Token", "NFT") {}

    function mint(address _to, uint256 _tokenId) external {
        _mint(_to, _tokenId);
    }
}

contract TimelockERC1155Mock is ERC1155 {
    constructor() ERC1155("https://token-cdn-domain/{id}.json") {}

    function mintBatch(address _to, uint256[] memory _ids, uint256[] memory _amounts, bytes memory _data) external {
        _mintBatch(_to, _ids, _amounts, _data);
    }
}

contract SaturnTimelockControllerPortTest is Test {
    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );
    event CallExecuted(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data);
    event CallSalt(bytes32 indexed id, bytes32 salt);
    event Cancelled(bytes32 indexed id);
    event MinDelayChange(uint256 oldDuration, uint256 newDuration);

    struct Operation {
        bytes32 id;
        address target;
        uint256 value;
        bytes data;
        bytes32 predecessor;
        bytes32 salt;
    }

    struct BatchOperation {
        bytes32 id;
        address[] targets;
        uint256[] values;
        bytes[] payloads;
        bytes32 predecessor;
        bytes32 salt;
    }

    SaturnTimelock internal mock;
    TimelockCallReceiverMock internal callReceiverMock;
    TimelockImplementation2 internal implementation2;

    address internal admin = makeAddr("admin");
    address internal proposer = makeAddr("proposer");
    address internal executor = makeAddr("executor");
    address internal other = makeAddr("other");

    uint256 internal constant MIN_DELAY = 1 days;
    bytes32 internal constant SALT = 0x025e7b0be353a74631ad648c667493c0e1cd31caa4cc2d3520fdc171ea0cc726;

    function setUp() public {
        vm.label(admin, "admin");
        vm.label(proposer, "proposer");
        vm.label(executor, "executor");
        vm.label(other, "other");

        mock = _deployTimelock(_singleton(executor));
        callReceiverMock = new TimelockCallReceiverMock();
        implementation2 = new TimelockImplementation2();
    }

    function _singleton(address _account) internal pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = _account;
    }

    function _deployTimelock(address[] memory _executors) internal returns (SaturnTimelock) {
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        return new SaturnTimelock(MIN_DELAY, proposers, _executors);
    }

    function _stateBitmap(TimelockController.OperationState _state) internal pure returns (bytes32) {
        return bytes32(uint256(1) << uint8(_state));
    }

    function _pendingBitmap() internal pure returns (bytes32) {
        return
            _stateBitmap(TimelockController.OperationState.Waiting)
                | _stateBitmap(TimelockController.OperationState.Ready);
    }

    function _makeOperation(address _target, uint256 _value, bytes memory _data, bytes32 _predecessor, bytes32 _salt)
        internal
        pure
        returns (Operation memory operation)
    {
        operation = Operation({
            id: keccak256(abi.encode(_target, _value, _data, _predecessor, _salt)),
            target: _target,
            value: _value,
            data: _data,
            predecessor: _predecessor,
            salt: _salt
        });
    }

    function _makeBatchOperation(uint256 _count) internal pure returns (BatchOperation memory operation) {
        address[] memory targets = new address[](_count);
        uint256[] memory values = new uint256[](_count);
        bytes[] memory payloads = new bytes[](_count);
        for (uint256 i = 0; i < _count; i++) {
            targets[i] = address(0xEd912250835c812D4516BBD80BdaEA1bB63a293C);
            values[i] = 0;
            payloads[i] = hex"2fcb7a88";
        }

        bytes32 predecessor = bytes32(0);
        bytes32 salt = 0x6cf9d042ade5de78bed9ffd075eb4b2a4f6b1736932c2dc8af517d6e066f51f5;
        operation = BatchOperation({
            id: keccak256(abi.encode(targets, values, payloads, predecessor, salt)),
            targets: targets,
            values: values,
            payloads: payloads,
            predecessor: predecessor,
            salt: salt
        });
    }

    function _schedule(Operation memory _operation) internal {
        vm.prank(proposer);
        mock.schedule(
            _operation.target, _operation.value, _operation.data, _operation.predecessor, _operation.salt, MIN_DELAY
        );
    }

    function _execute(Operation memory _operation) internal {
        vm.prank(executor);
        mock.execute(_operation.target, _operation.value, _operation.data, _operation.predecessor, _operation.salt);
    }

    function _scheduleBatch(BatchOperation memory _operation) internal {
        vm.prank(proposer);
        mock.scheduleBatch(
            _operation.targets,
            _operation.values,
            _operation.payloads,
            _operation.predecessor,
            _operation.salt,
            MIN_DELAY
        );
    }

    function _executeBatch(BatchOperation memory _operation) internal {
        vm.prank(executor);
        mock.executeBatch(
            _operation.targets, _operation.values, _operation.payloads, _operation.predecessor, _operation.salt
        );
    }

    function _warpToReady(bytes32 _id) internal {
        vm.warp(mock.getTimestamp(_id));
    }

    function _assertNoCallSalt() internal view {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 callSaltTopic = keccak256("CallSalt(bytes32,bytes32)");

        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != callSaltTopic);
        }
    }

    function _expectUnexpectedState(bytes32 _id, bytes32 _expectedStates) internal {
        vm.expectRevert(
            abi.encodeWithSelector(TimelockController.TimelockUnexpectedOperationState.selector, _id, _expectedStates)
        );
    }

    function _expectUnauthorized(address _account, bytes32 _role) internal {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _account, _role)
        );
    }

    // ============ Initial State ============

    function test_initialState() public view {
        assertEq(mock.getMinDelay(), MIN_DELAY);
        assertEq(mock.DEFAULT_ADMIN_ROLE(), bytes32(0));
        assertEq(mock.PROPOSER_ROLE(), keccak256("PROPOSER_ROLE"));
        assertEq(mock.EXECUTOR_ROLE(), keccak256("EXECUTOR_ROLE"));
        assertEq(mock.CANCELLER_ROLE(), keccak256("CANCELLER_ROLE"));

        assertTrue(mock.hasRole(mock.PROPOSER_ROLE(), proposer));
        assertTrue(mock.hasRole(mock.CANCELLER_ROLE(), proposer));
        assertFalse(mock.hasRole(mock.EXECUTOR_ROLE(), proposer));

        assertFalse(mock.hasRole(mock.PROPOSER_ROLE(), executor));
        assertFalse(mock.hasRole(mock.CANCELLER_ROLE(), executor));
        assertTrue(mock.hasRole(mock.EXECUTOR_ROLE(), executor));

        assertTrue(mock.hasRole(mock.DEFAULT_ADMIN_ROLE(), address(mock)));
        assertFalse(mock.hasRole(mock.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_supportsERC1155ReceiverInterface() public view {
        assertTrue(mock.supportsInterface(type(IERC165).interfaceId));
        assertTrue(mock.supportsInterface(type(IERC1155Receiver).interfaceId));
    }

    // ============ Operation Hashing ============

    function test_hashOperation() public view {
        Operation memory operation = _makeOperation(
            address(0x29cebEfe301c6cE1bb36b58654FEA275e1cAcc83),
            0xf94fdd6e21da21d2,
            hex"a3bc5104",
            0xba41db3be0a9929145cfe480bd0f1f003689104d275ae912099f925df424ef94,
            0x60d9109846ab510ed75c15f979ae366a8a2ace11d34ba9788c13ac296db50e6e
        );

        assertEq(
            mock.hashOperation(
                operation.target, operation.value, operation.data, operation.predecessor, operation.salt
            ),
            operation.id
        );
    }

    function test_hashOperationBatch() public view {
        uint256 count = 8;
        address[] memory targets = new address[](count);
        uint256[] memory values = new uint256[](count);
        bytes[] memory payloads = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            targets[i] = address(0x2D5f21620E56531C1d59c2dF9B8e95d129571F71);
            values[i] = 0x2b993cfce932ccee;
            payloads[i] = hex"cf51966b";
        }

        bytes32 predecessor = 0xce8f45069cc71d25f71ba05062de1a3974f9849b004de64a70998bca9d29c2e7;
        bytes32 salt = 0x8952d74c110f72bfe5accdf828c74d53a7dfb71235dfa8a1e8c75d8576b372ff;

        assertEq(
            mock.hashOperationBatch(targets, values, payloads, predecessor, salt),
            keccak256(abi.encode(targets, values, payloads, predecessor, salt))
        );
    }

    // ============ Simple Schedule ============

    function test_schedule_proposerCanSchedule() public {
        Operation memory operation =
            _makeOperation(address(0x31754f590B97fD975Eb86938f18Cc304E264D2F2), 0, hex"3bf92ccc", bytes32(0), SALT);

        vm.expectEmit(true, true, false, true, address(mock));
        emit CallScheduled(
            operation.id, 0, operation.target, operation.value, operation.data, operation.predecessor, MIN_DELAY
        );
        vm.expectEmit(true, false, false, true, address(mock));
        emit CallSalt(operation.id, operation.salt);

        uint256 scheduledAt = block.timestamp;
        _schedule(operation);

        assertEq(mock.getTimestamp(operation.id), scheduledAt + MIN_DELAY);
        assertEq(uint8(mock.getOperationState(operation.id)), uint8(TimelockController.OperationState.Waiting));
    }

    function test_schedule_preventsOverwritingActiveOperation() public {
        Operation memory operation =
            _makeOperation(address(0x31754f590B97fD975Eb86938f18Cc304E264D2F2), 0, hex"3bf92ccc", bytes32(0), SALT);
        _schedule(operation);

        _expectUnexpectedState(operation.id, _stateBitmap(TimelockController.OperationState.Unset));
        _schedule(operation);
    }

    function test_schedule_preventsNonProposer() public {
        Operation memory operation =
            _makeOperation(address(0x31754f590B97fD975Eb86938f18Cc304E264D2F2), 0, hex"3bf92ccc", bytes32(0), SALT);

        _expectUnauthorized(other, mock.PROPOSER_ROLE());
        vm.prank(other);
        mock.schedule(
            operation.target, operation.value, operation.data, operation.predecessor, operation.salt, MIN_DELAY
        );
    }

    function test_schedule_enforcesMinimumDelay() public {
        Operation memory operation =
            _makeOperation(address(0x31754f590B97fD975Eb86938f18Cc304E264D2F2), 0, hex"3bf92ccc", bytes32(0), SALT);

        vm.expectRevert(
            abi.encodeWithSelector(TimelockController.TimelockInsufficientDelay.selector, MIN_DELAY - 1, MIN_DELAY)
        );
        vm.prank(proposer);
        mock.schedule(
            operation.target, operation.value, operation.data, operation.predecessor, operation.salt, MIN_DELAY - 1
        );
    }

    function test_schedule_zeroSaltDoesNotEmitCallSalt() public {
        Operation memory operation = _makeOperation(
            address(0x31754f590B97fD975Eb86938f18Cc304E264D2F2), 0, hex"3bf92ccc", bytes32(0), bytes32(0)
        );

        vm.recordLogs();
        _schedule(operation);
        _assertNoCallSalt();
    }

    // ============ Simple Execute ============

    function test_execute_revertsIfOperationNotScheduled() public {
        Operation memory operation =
            _makeOperation(address(0xAe22104DCD970750610E6FE15E623468A98b15f7), 0, hex"13e414de", bytes32(0), SALT);

        _expectUnexpectedState(operation.id, _stateBitmap(TimelockController.OperationState.Ready));
        _execute(operation);
    }

    function test_execute_revertsTooEarlyImmediately() public {
        Operation memory operation =
            _makeOperation(address(0xAe22104DCD970750610E6FE15E623468A98b15f7), 0, hex"13e414de", bytes32(0), SALT);
        _schedule(operation);

        _expectUnexpectedState(operation.id, _stateBitmap(TimelockController.OperationState.Ready));
        _execute(operation);
    }

    function test_execute_revertsTooEarlyBeforeTimestamp() public {
        Operation memory operation =
            _makeOperation(address(0xAe22104DCD970750610E6FE15E623468A98b15f7), 0, hex"13e414de", bytes32(0), SALT);
        _schedule(operation);
        vm.warp(mock.getTimestamp(operation.id) - 5);

        _expectUnexpectedState(operation.id, _stateBitmap(TimelockController.OperationState.Ready));
        _execute(operation);
    }

    function test_execute_executorCanExecuteOnTime() public {
        Operation memory operation =
            _makeOperation(address(0xAe22104DCD970750610E6FE15E623468A98b15f7), 0, hex"13e414de", bytes32(0), SALT);
        _schedule(operation);
        _warpToReady(operation.id);

        vm.expectEmit(true, true, false, true, address(mock));
        emit CallExecuted(operation.id, 0, operation.target, operation.value, operation.data);
        _execute(operation);

        assertTrue(mock.isOperationDone(operation.id));
        assertEq(uint8(mock.getOperationState(operation.id)), uint8(TimelockController.OperationState.Done));
    }

    function test_execute_preventsNonExecutor() public {
        Operation memory operation =
            _makeOperation(address(0xAe22104DCD970750610E6FE15E623468A98b15f7), 0, hex"13e414de", bytes32(0), SALT);
        _schedule(operation);
        _warpToReady(operation.id);

        _expectUnauthorized(other, mock.EXECUTOR_ROLE());
        vm.prank(other);
        mock.execute(operation.target, operation.value, operation.data, operation.predecessor, operation.salt);
    }

    function test_execute_preventsReentrancyExecution() public {
        TimelockReentrant reentrant = new TimelockReentrant();
        address[] memory executors = new address[](2);
        executors[0] = executor;
        executors[1] = address(reentrant);
        SaturnTimelock timelock = _deployTimelock(executors);

        Operation memory operation =
            _makeOperation(address(reentrant), 0, abi.encodeCall(TimelockReentrant.reenter, ()), bytes32(0), SALT);

        vm.prank(proposer);
        timelock.schedule(
            operation.target, operation.value, operation.data, operation.predecessor, operation.salt, MIN_DELAY
        );
        vm.warp(timelock.getTimestamp(operation.id));

        bytes memory reenterData = abi.encodeCall(
            TimelockController.execute,
            (operation.target, operation.value, operation.data, operation.predecessor, operation.salt)
        );
        reentrant.enableReentrancy(timelock, reenterData);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                operation.id,
                _stateBitmap(TimelockController.OperationState.Ready)
            )
        );
        vm.prank(executor);
        timelock.execute(operation.target, operation.value, operation.data, operation.predecessor, operation.salt);

        reentrant.disableReentrancy();

        vm.expectEmit(true, true, false, true, address(timelock));
        emit CallExecuted(operation.id, 0, operation.target, operation.value, operation.data);
        vm.prank(executor);
        timelock.execute(operation.target, operation.value, operation.data, operation.predecessor, operation.salt);
    }

    // ============ Batch Schedule ============

    function test_scheduleBatch_proposerCanSchedule() public {
        BatchOperation memory operation = _makeBatchOperation(8);

        for (uint256 i = 0; i < operation.targets.length; i++) {
            vm.expectEmit(true, true, false, true, address(mock));
            emit CallScheduled(
                operation.id,
                i,
                operation.targets[i],
                operation.values[i],
                operation.payloads[i],
                operation.predecessor,
                MIN_DELAY
            );
        }
        vm.expectEmit(true, false, false, true, address(mock));
        emit CallSalt(operation.id, operation.salt);

        uint256 scheduledAt = block.timestamp;
        _scheduleBatch(operation);

        assertEq(mock.getTimestamp(operation.id), scheduledAt + MIN_DELAY);
    }

    function test_scheduleBatch_preventsOverwritingActiveOperation() public {
        BatchOperation memory operation = _makeBatchOperation(8);
        _scheduleBatch(operation);

        _expectUnexpectedState(operation.id, _stateBitmap(TimelockController.OperationState.Unset));
        _scheduleBatch(operation);
    }

    function test_scheduleBatch_revertsWhenValuesLengthMismatch() public {
        BatchOperation memory operation = _makeBatchOperation(8);
        uint256[] memory emptyValues = new uint256[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockInvalidOperationLength.selector,
                operation.targets.length,
                operation.payloads.length,
                emptyValues.length
            )
        );
        vm.prank(proposer);
        mock.scheduleBatch(
            operation.targets, emptyValues, operation.payloads, operation.predecessor, operation.salt, MIN_DELAY
        );
    }

    function test_scheduleBatch_revertsWhenPayloadsLengthMismatch() public {
        BatchOperation memory operation = _makeBatchOperation(8);
        bytes[] memory emptyPayloads = new bytes[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockInvalidOperationLength.selector,
                operation.targets.length,
                emptyPayloads.length,
                operation.values.length
            )
        );
        vm.prank(proposer);
        mock.scheduleBatch(
            operation.targets, operation.values, emptyPayloads, operation.predecessor, operation.salt, MIN_DELAY
        );
    }

    function test_scheduleBatch_preventsNonProposer() public {
        BatchOperation memory operation = _makeBatchOperation(8);

        _expectUnauthorized(other, mock.PROPOSER_ROLE());
        vm.prank(other);
        mock.scheduleBatch(
            operation.targets, operation.values, operation.payloads, operation.predecessor, operation.salt, MIN_DELAY
        );
    }

    function test_scheduleBatch_enforcesMinimumDelay() public {
        BatchOperation memory operation = _makeBatchOperation(8);

        vm.expectRevert(
            abi.encodeWithSelector(TimelockController.TimelockInsufficientDelay.selector, MIN_DELAY - 1, MIN_DELAY)
        );
        vm.prank(proposer);
        mock.scheduleBatch(
            operation.targets,
            operation.values,
            operation.payloads,
            operation.predecessor,
            operation.salt,
            MIN_DELAY - 1
        );
    }

    // ============ Batch Execute ============

    function test_executeBatch_revertsIfOperationNotScheduled() public {
        BatchOperation memory operation = _makeBatchOperation(8);

        _expectUnexpectedState(operation.id, _stateBitmap(TimelockController.OperationState.Ready));
        _executeBatch(operation);
    }

    function test_executeBatch_revertsTooEarlyImmediately() public {
        BatchOperation memory operation = _makeBatchOperation(8);
        _scheduleBatch(operation);

        _expectUnexpectedState(operation.id, _stateBitmap(TimelockController.OperationState.Ready));
        _executeBatch(operation);
    }

    function test_executeBatch_revertsTooEarlyBeforeTimestamp() public {
        BatchOperation memory operation = _makeBatchOperation(8);
        _scheduleBatch(operation);
        vm.warp(mock.getTimestamp(operation.id) - 5);

        _expectUnexpectedState(operation.id, _stateBitmap(TimelockController.OperationState.Ready));
        _executeBatch(operation);
    }

    function test_executeBatch_executorCanExecuteOnTime() public {
        BatchOperation memory operation = _makeBatchOperation(8);
        _scheduleBatch(operation);
        _warpToReady(operation.id);

        for (uint256 i = 0; i < operation.targets.length; i++) {
            vm.expectEmit(true, true, false, true, address(mock));
            emit CallExecuted(operation.id, i, operation.targets[i], operation.values[i], operation.payloads[i]);
        }
        _executeBatch(operation);

        assertTrue(mock.isOperationDone(operation.id));
    }

    function test_executeBatch_preventsNonExecutor() public {
        BatchOperation memory operation = _makeBatchOperation(8);
        _scheduleBatch(operation);
        _warpToReady(operation.id);

        _expectUnauthorized(other, mock.EXECUTOR_ROLE());
        vm.prank(other);
        mock.executeBatch(
            operation.targets, operation.values, operation.payloads, operation.predecessor, operation.salt
        );
    }

    function test_executeBatch_revertsWhenTargetsLengthMismatch() public {
        BatchOperation memory operation = _makeBatchOperation(8);
        _scheduleBatch(operation);
        _warpToReady(operation.id);

        address[] memory emptyTargets = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockInvalidOperationLength.selector,
                emptyTargets.length,
                operation.payloads.length,
                operation.values.length
            )
        );
        vm.prank(executor);
        mock.executeBatch(emptyTargets, operation.values, operation.payloads, operation.predecessor, operation.salt);
    }

    function test_executeBatch_revertsWhenValuesLengthMismatch() public {
        BatchOperation memory operation = _makeBatchOperation(8);
        _scheduleBatch(operation);
        _warpToReady(operation.id);

        uint256[] memory emptyValues = new uint256[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockInvalidOperationLength.selector,
                operation.targets.length,
                operation.payloads.length,
                emptyValues.length
            )
        );
        vm.prank(executor);
        mock.executeBatch(operation.targets, emptyValues, operation.payloads, operation.predecessor, operation.salt);
    }

    function test_executeBatch_revertsWhenPayloadsLengthMismatch() public {
        BatchOperation memory operation = _makeBatchOperation(8);
        _scheduleBatch(operation);
        _warpToReady(operation.id);

        bytes[] memory emptyPayloads = new bytes[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockInvalidOperationLength.selector,
                operation.targets.length,
                emptyPayloads.length,
                operation.values.length
            )
        );
        vm.prank(executor);
        mock.executeBatch(operation.targets, operation.values, emptyPayloads, operation.predecessor, operation.salt);
    }

    function test_executeBatch_preventsReentrancyExecution() public {
        TimelockReentrant reentrant = new TimelockReentrant();
        address[] memory executors = new address[](2);
        executors[0] = executor;
        executors[1] = address(reentrant);
        SaturnTimelock timelock = _deployTimelock(executors);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        targets[0] = address(reentrant);
        values[0] = 0;
        payloads[0] = abi.encodeCall(TimelockReentrant.reenter, ());

        BatchOperation memory operation = BatchOperation({
            id: keccak256(abi.encode(targets, values, payloads, bytes32(0), SALT)),
            targets: targets,
            values: values,
            payloads: payloads,
            predecessor: bytes32(0),
            salt: SALT
        });

        vm.prank(proposer);
        timelock.scheduleBatch(
            operation.targets, operation.values, operation.payloads, operation.predecessor, operation.salt, MIN_DELAY
        );
        vm.warp(timelock.getTimestamp(operation.id));

        bytes memory reenterData = abi.encodeCall(
            TimelockController.executeBatch,
            (operation.targets, operation.values, operation.payloads, operation.predecessor, operation.salt)
        );
        reentrant.enableReentrancy(timelock, reenterData);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                operation.id,
                _stateBitmap(TimelockController.OperationState.Ready)
            )
        );
        vm.prank(executor);
        timelock.executeBatch(
            operation.targets, operation.values, operation.payloads, operation.predecessor, operation.salt
        );

        reentrant.disableReentrancy();

        vm.expectEmit(true, true, false, true, address(timelock));
        emit CallExecuted(operation.id, 0, operation.targets[0], operation.values[0], operation.payloads[0]);
        vm.prank(executor);
        timelock.executeBatch(
            operation.targets, operation.values, operation.payloads, operation.predecessor, operation.salt
        );
    }

    function test_executeBatch_revertsOnPartialExecutionFailure() public {
        address[] memory targets = new address[](3);
        uint256[] memory values = new uint256[](3);
        bytes[] memory payloads = new bytes[](3);

        targets[0] = address(callReceiverMock);
        targets[1] = address(callReceiverMock);
        targets[2] = address(callReceiverMock);
        payloads[0] = abi.encodeCall(TimelockCallReceiverMock.mockFunction, ());
        payloads[1] = abi.encodeCall(TimelockCallReceiverMock.mockFunctionRevertsNoReason, ());
        payloads[2] = abi.encodeCall(TimelockCallReceiverMock.mockFunction, ());

        BatchOperation memory operation = BatchOperation({
            id: keccak256(
                abi.encode(
                    targets,
                    values,
                    payloads,
                    bytes32(0),
                    0x8ac04aa0d6d66b8812fb41d39638d37af0a9ab11da507afd65c509f8ed079d3e
                )
            ),
            targets: targets,
            values: values,
            payloads: payloads,
            predecessor: bytes32(0),
            salt: 0x8ac04aa0d6d66b8812fb41d39638d37af0a9ab11da507afd65c509f8ed079d3e
        });

        _scheduleBatch(operation);
        _warpToReady(operation.id);

        vm.expectRevert(Errors.FailedCall.selector);
        _executeBatch(operation);
    }

    // ============ Cancel ============

    function test_cancel_proposerCanCancel() public {
        Operation memory operation =
            _makeOperation(address(0xC6837c44AA376dbe1d2709F13879E040CAb653ca), 0, hex"296e58dd", bytes32(0), SALT);
        _schedule(operation);

        vm.expectEmit(true, false, false, false, address(mock));
        emit Cancelled(operation.id);

        vm.prank(proposer);
        mock.cancel(operation.id);

        assertFalse(mock.isOperation(operation.id));
    }

    function test_cancel_cannotCancelInvalidOperation() public {
        _expectUnexpectedState(bytes32(0), _pendingBitmap());
        vm.prank(proposer);
        mock.cancel(bytes32(0));
    }

    function test_cancel_preventsNonCanceller() public {
        Operation memory operation =
            _makeOperation(address(0xC6837c44AA376dbe1d2709F13879E040CAb653ca), 0, hex"296e58dd", bytes32(0), SALT);
        _schedule(operation);

        _expectUnauthorized(other, mock.CANCELLER_ROLE());
        vm.prank(other);
        mock.cancel(operation.id);
    }

    // ============ Maintenance ============

    function test_updateDelay_preventsUnauthorizedCaller() public {
        vm.expectRevert(abi.encodeWithSelector(TimelockController.TimelockUnauthorizedCaller.selector, other));
        vm.prank(other);
        mock.updateDelay(0);
    }

    function test_updateDelay_timelockScheduledMaintenance() public {
        uint256 newDelay = 6 hours;
        Operation memory operation = _makeOperation(
            address(mock),
            0,
            abi.encodeCall(TimelockController.updateDelay, (newDelay)),
            bytes32(0),
            0xf8e775b2c5f4d66fb5c7fa800f35ef518c262b6014b3c0aee6ea21bff157f108
        );

        _schedule(operation);
        _warpToReady(operation.id);

        vm.expectEmit(false, false, false, true, address(mock));
        emit MinDelayChange(MIN_DELAY, newDelay);
        _execute(operation);

        assertEq(mock.getMinDelay(), newDelay);
    }

    // ============ Dependency ============

    function test_dependency_cannotExecuteBeforeDependency() public {
        Operation memory operation1 = _makeOperation(
            address(0xdE66bD4c97304200A95aE0AadA32d6d01A867E39),
            0,
            hex"01dc731a",
            bytes32(0),
            0x64e932133c7677402ead2926f86205e2ca4686aebecf5a8077627092b9bb2feb
        );
        Operation memory operation2 = _makeOperation(
            address(0x3c7944a3F1ee7fc8c5A5134ba7c79D11c3A1FCa3),
            0,
            hex"8f531849",
            operation1.id,
            0x036e1311cac523f9548e6461e29fb1f8f9196b91910a41711ea22f5de48df07d
        );
        _schedule(operation1);
        _schedule(operation2);
        _warpToReady(operation2.id);

        vm.expectRevert(
            abi.encodeWithSelector(TimelockController.TimelockUnexecutedPredecessor.selector, operation1.id)
        );
        _execute(operation2);
    }

    function test_dependency_canExecuteAfterDependency() public {
        Operation memory operation1 = _makeOperation(
            address(0xdE66bD4c97304200A95aE0AadA32d6d01A867E39),
            0,
            hex"01dc731a",
            bytes32(0),
            0x64e932133c7677402ead2926f86205e2ca4686aebecf5a8077627092b9bb2feb
        );
        Operation memory operation2 = _makeOperation(
            address(0x3c7944a3F1ee7fc8c5A5134ba7c79D11c3A1FCa3),
            0,
            hex"8f531849",
            operation1.id,
            0x036e1311cac523f9548e6461e29fb1f8f9196b91910a41711ea22f5de48df07d
        );
        _schedule(operation1);
        _schedule(operation2);
        _warpToReady(operation2.id);

        _execute(operation1);
        _execute(operation2);

        assertTrue(mock.isOperationDone(operation1.id));
        assertTrue(mock.isOperationDone(operation2.id));
    }

    // ============ Usage Scenario ============

    function test_usage_call() public {
        Operation memory operation = _makeOperation(
            address(implementation2),
            0,
            abi.encodeCall(TimelockImplementation2.setValue, (42)),
            bytes32(0),
            0x8043596363daefc89977b25f9d9b4d06c3910959ef0c4d213557a903e1b555e2
        );
        _schedule(operation);
        _warpToReady(operation.id);
        _execute(operation);

        assertEq(implementation2.getValue(), 42);
    }

    function test_usage_callReverting() public {
        Operation memory operation = _makeOperation(
            address(callReceiverMock),
            0,
            abi.encodeCall(TimelockCallReceiverMock.mockFunctionRevertsNoReason, ()),
            bytes32(0),
            0xb1b1b276fdf1a28d1e00537ea73b04d56639128b08063c1a2f70a52e38cba693
        );
        _schedule(operation);
        _warpToReady(operation.id);

        vm.expectRevert(Errors.FailedCall.selector);
        _execute(operation);
    }

    function test_usage_callThrow() public {
        Operation memory operation = _makeOperation(
            address(callReceiverMock),
            0,
            abi.encodeCall(TimelockCallReceiverMock.mockFunctionThrows, ()),
            bytes32(0),
            0xe5ca79f295fc8327ee8a765fe19afb58f4a0cbc5053642bfdd7e73bc68e0fc67
        );
        _schedule(operation);
        _warpToReady(operation.id);

        vm.expectRevert(stdError.assertionError);
        _execute(operation);
    }

    function test_usage_callOutOfGas() public {
        Operation memory operation = _makeOperation(
            address(callReceiverMock),
            0,
            abi.encodeCall(TimelockCallReceiverMock.mockFunctionOutOfGas, ()),
            bytes32(0),
            0xf3274ce7c394c5b629d5215723563a744b817e1730cca5587c567099a14578fd
        );
        _schedule(operation);
        _warpToReady(operation.id);

        bytes memory callData = abi.encodeCall(
            TimelockController.execute,
            (operation.target, operation.value, operation.data, operation.predecessor, operation.salt)
        );
        vm.prank(executor);
        (bool success, bytes memory returndata) = address(mock).call{gas: 100_000}(callData);

        assertFalse(success);
        assertEq(bytes4(returndata), Errors.FailedCall.selector);
    }

    function test_usage_callPayableWithEth() public {
        Operation memory operation = _makeOperation(
            address(callReceiverMock),
            1,
            abi.encodeCall(TimelockCallReceiverMock.mockFunction, ()),
            bytes32(0),
            0x5ab73cd33477dcd36c1e05e28362719d0ed59a7b9ff14939de63a43073dc1f44
        );
        _schedule(operation);
        _warpToReady(operation.id);

        assertEq(address(mock).balance, 0);
        assertEq(address(callReceiverMock).balance, 0);

        vm.deal(executor, 1);
        vm.prank(executor);
        mock.execute{value: 1}(operation.target, operation.value, operation.data, operation.predecessor, operation.salt);

        assertEq(address(mock).balance, 0);
        assertEq(address(callReceiverMock).balance, 1);
    }

    function test_usage_callNonpayableWithEth() public {
        Operation memory operation = _makeOperation(
            address(callReceiverMock),
            1,
            abi.encodeCall(TimelockCallReceiverMock.mockFunctionNonPayable, ()),
            bytes32(0),
            0xb78edbd920c7867f187e5aa6294ae5a656cfbf0dea1ccdca3751b740d0f2bdf8
        );
        _schedule(operation);
        _warpToReady(operation.id);

        assertEq(address(mock).balance, 0);
        assertEq(address(callReceiverMock).balance, 0);

        vm.expectRevert(Errors.FailedCall.selector);
        _execute(operation);

        assertEq(address(mock).balance, 0);
        assertEq(address(callReceiverMock).balance, 0);
    }

    function test_usage_callRevertingWithEth() public {
        Operation memory operation = _makeOperation(
            address(callReceiverMock),
            1,
            abi.encodeCall(TimelockCallReceiverMock.mockFunctionRevertsNoReason, ()),
            bytes32(0),
            0xdedb4563ef0095db01d81d3f2decf57cf83e4a72aa792af14c43a792b56f4de6
        );
        _schedule(operation);
        _warpToReady(operation.id);

        assertEq(address(mock).balance, 0);
        assertEq(address(callReceiverMock).balance, 0);

        vm.expectRevert(Errors.FailedCall.selector);
        _execute(operation);

        assertEq(address(mock).balance, 0);
        assertEq(address(callReceiverMock).balance, 0);
    }

    // ============ Safe Receive ============

    function test_safeReceive_canReceiveERC721SafeTransfer() public {
        uint256 tokenId = 1;
        TimelockERC721Mock token = new TimelockERC721Mock();
        token.mint(other, tokenId);

        vm.prank(other);
        token.safeTransferFrom(other, address(mock), tokenId);

        assertEq(token.ownerOf(tokenId), address(mock));
    }

    function test_safeReceive_canReceiveERC1155SafeTransfer() public {
        TimelockERC1155Mock token = new TimelockERC1155Mock();
        uint256[] memory ids = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        amounts[0] = 1000;
        amounts[1] = 2000;
        amounts[2] = 3000;
        token.mintBatch(other, ids, amounts, "");

        vm.prank(other);
        token.safeTransferFrom(other, address(mock), ids[0], amounts[0], "");

        assertEq(token.balanceOf(address(mock), ids[0]), amounts[0]);
    }

    function test_safeReceive_canReceiveERC1155SafeBatchTransfer() public {
        TimelockERC1155Mock token = new TimelockERC1155Mock();
        uint256[] memory ids = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        amounts[0] = 1000;
        amounts[1] = 2000;
        amounts[2] = 3000;
        token.mintBatch(other, ids, amounts, "");

        vm.prank(other);
        token.safeBatchTransferFrom(other, address(mock), ids, amounts, "");

        assertEq(token.balanceOf(address(mock), ids[0]), amounts[0]);
        assertEq(token.balanceOf(address(mock), ids[1]), amounts[1]);
        assertEq(token.balanceOf(address(mock), ids[2]), amounts[2]);
    }
}
