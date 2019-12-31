pragma solidity ^0.4.19;

contract DappBase {
    function getCurNodeList() public view returns (address[] nodeList);
}

contract Relay {
    
    function notify(uint256 time, uint256 blknum) public returns (bool success);
}

contract CBEReward {
    
    struct Task {
        bytes32 hash;
        address[] voters;
        bool distDone;
    }
    
    struct Reward {
        address[] beneficiaryAddr;
        uint256[] reward;
    }
    
    struct RewardInfo {
        uint256 minerCount;
        uint256 beneficiaryCount;
        uint256 blkNum;
        uint256 hasBeenCount;
        mapping(uint256 => Reward) rewards;
        uint256[] indexList;
    }
    
    address internal owner;
    mapping(address => uint) public admins;
    uint256 public awardAmount;  // coin
    address public dappBaseAddr;
    uint256 public distributePaymentTime;
	uint256 public distributePaymentStartTime;
	uint256 public per_postReward_acc_num = 300;
	uint256 public numerator = 1000;
	
    mapping(bytes32 => Task) task;
    mapping(uint256 => uint256) public rewardStatus;
    mapping(uint256 => RewardInfo) public rewardRecord;

    Relay internal RELAY = Relay(0x0000000000000000000000000000000000000010);
    address[] scsNodeList;
    function CBEReward(uint256 DistributePaymentTime, address DappBaseAddr) public payable {
        owner = msg.sender;
		awardAmount = 406080 * 10 ** 18;
        distributePaymentTime = DistributePaymentTime;
        distributePaymentStartTime = DistributePaymentTime;
		dappBaseAddr = DappBaseAddr;
    }
    
    function setOwner(address _owner) public {
        require(msg.sender == owner);
        owner = _owner;
    }
    
    function addAdmin(address admin) public {
        require(msg.sender == owner);
        admins[admin] = 1;
    }

    function removeAdmin(address admin) public {
        require(msg.sender == owner);
        admins[admin] = 0;
    }

    function setAwardAmount(uint256 amount) public {
        require(msg.sender == owner || admins[msg.sender] == 1);
        awardAmount = amount;
    }
    
	function setDistributePaymentTime(uint256 time) public {
        require(msg.sender == owner || admins[msg.sender] == 1);
        
        distributePaymentTime = time;
    }
    
    function setDistributePaymentStartTime(uint256 time) public {
        require(msg.sender == owner || admins[msg.sender] == 1);

        distributePaymentStartTime = time;
    }
    
    function setNumerator(uint256 num) public {
        require(msg.sender == owner || admins[msg.sender] == 1);
        
        numerator = num;
    }

    function setPerPostRewardAccNum(uint256 num) public {
        require(msg.sender == owner || admins[msg.sender] == 1);
        
        per_postReward_acc_num = num;
    }
    
    function getAwardAmountByTime(uint256 time) public view returns (uint256) {
        uint256 num = (time - distributePaymentStartTime) / 4 years;
        return awardAmount / (1 << num);
    }

    function postRewardInfo(uint256 time, uint256 blkNum, uint256 minerCount, uint256 beneficiaryCount) public returns (bool) {
        require(rewardStatus[time] == 0);
        require(now > distributePaymentTime + 1 days);
        require(time >= distributePaymentTime + 1 days);
        require((time - distributePaymentTime) % 1 days == 0);
        DappBase dapp = DappBase(dappBaseAddr);
        scsNodeList = dapp.getCurNodeList();
        require(haveAddress(scsNodeList, msg.sender));
        uint256 award = getAwardAmountByTime(time);
        if (this.balance > award + 10 ** 18) {
            bytes32 hash = sha3(time, blkNum, minerCount, beneficiaryCount);
            if(!haveAddress(task[hash].voters, msg.sender)) {
                task[hash].voters.push(msg.sender);
                if(task[hash].voters.length > scsNodeList.length/2 ) {
                    //distribute
                    task[hash].distDone = true;
                    rewardRecord[time].minerCount = minerCount;
                    rewardRecord[time].beneficiaryCount = beneficiaryCount;
                    rewardRecord[time].blkNum = blkNum;
                    distributePaymentTime = time;
                    rewardStatus[time] = 1;
                    RELAY.notify(time, blkNum);
                }
            }
        } else {
            return false;
        }
        return true;
    }
    
    function postReward(uint256 time, uint256 blkNum, uint256 minerCount, uint256 beneficiaryCount, uint256 index, address[] nodeAddr, uint256[] reward) public {
        require(rewardStatus[time] == 1);
        require(rewardRecord[time].blkNum == blkNum);
        require(rewardRecord[time].minerCount == minerCount);
        require(rewardRecord[time].beneficiaryCount == beneficiaryCount);
        require(rewardRecord[time].hasBeenCount + nodeAddr.length <= rewardRecord[time].beneficiaryCount);
        require(rewardRecord[time].rewards[index].beneficiaryAddr.length == 0);
        DappBase dapp = DappBase(dappBaseAddr);
        scsNodeList = dapp.getCurNodeList();
        require(haveAddress(scsNodeList, msg.sender));
        require(nodeAddr.length == reward.length);

        bytes32 hash = sha3(time, blkNum, minerCount, beneficiaryCount, index, nodeAddr, reward);
        if( task[hash].distDone) return;
        if(!haveAddress(task[hash].voters, msg.sender)) {
            task[hash].voters.push(msg.sender);
            if(task[hash].voters.length > scsNodeList.length/2 ) {
                //distribute
                task[hash].distDone = true;
                for(uint256 i=0; i<nodeAddr.length; i++ ) {
                    rewardRecord[time].rewards[index].beneficiaryAddr.push(nodeAddr[i]);
                    rewardRecord[time].rewards[index].reward.push(reward[i]);
                    uint256 size;
                    address addr = nodeAddr[i];
                    assembly {
                        size := extcodesize(addr)
                    }
                    if (size == 0) {
                        nodeAddr[i].transfer(reward[i]);
                    }
                }
                rewardRecord[time].indexList.push(index);
                rewardRecord[time].hasBeenCount += nodeAddr.length;
                if (rewardRecord[time].hasBeenCount == rewardRecord[time].beneficiaryCount) {
                    rewardStatus[time] = 2;
                }
            }
        }
    }
    
    function haveAddress(address[] addrs, address addr) private returns (bool) {
        uint256 i;
        for (i = 0; i < addrs.length; i++) {
            if(addrs[i] == addr) {
                return true;
            }
        }
        return false;
    }
}