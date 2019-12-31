pragma solidity ^0.4.19;
pragma experimental ABIEncoderV2;
// ----------------------------------------------------------------------------
// Precompiled contract executed by Moac MicroChain SCS Virtual Machine
// ----------------------------------------------------------------------------


contract CBE {

    enum AccessType {read, write, remove, verify}

    struct File {
        string fileHash;
        string fileName;
        uint256 fileSize;
        address fileOwner;
        uint256 status;
        uint256 centerNodeId;
        address[] mScsIdList;
        address[] succSyncMScsIdList;
    }
    
    struct MinerNode {
	    address sender;
        address beneficiary;		//收益地址
        uint256 size;
        uint256 bond;   // 押金数量
        uint status;				//状态  1 完成注册 2 注销中 3 已退出
		uint256 weight;		//矿机规格 也是计算矿机收益权重
		address scsId;  	//超级节点ID
		uint256 withdrawBlock;		//退出要求的区块高度
    }

    struct SuperNode {
        address beneficiary;
        uint8 status;  				//状态 1 正常  2 注销中 3 已退出
		uint256 bond;   			// 押金数量
		uint256 minerNodeCount;
		address[] minerNodeList;
		uint256 size;				//此超级节点下面所有矿机的存储总量,单位T
		mapping(address => WithdrawSuperNode) withdrawSuperNodeMap;
    }
    
    struct WithdrawSuperNode {
        uint256 bond;   			// 押金数量
        uint256 withdrawBlock;		//退出要求的区块高度
    }
    
    address internal owner;
    mapping(address => uint) public admins;
    uint256 public validatorBond;
    uint256 public nodeBond;
    uint256 public minerNodeCount = 0;
    mapping(uint256 => uint256) public capacityMapping;
    mapping(address => SuperNode) public superNodeMapping;
    address[] public superNodeList;
    mapping(address => address) public userMap;
    mapping(address => MinerNode) public nodeMapping;
    mapping(address => string) public minerNodePeerMap;
    address[] public minerNodeList;
    mapping(uint256 => string) public centerNodePeerMap;
    uint256[] centerNodeIdList;
    uint256 fileIdNum;
    mapping(uint256 => File) public fileMapping;
    uint256[] public fileList;
    uint256 public fileCount;
    mapping(address => uint256[]) private myFileList;

    // mapping(address => VerifyTransaction) public verifyGroupMapping;


    address[] addressArr;
    address[] addressArr1;
    address[] addressArr2;
    uint256[] uint256Arr;
    string[] stringArr;

    function CBE(uint256 ValidatorBond, uint256 NodeBond) public payable {
        owner = msg.sender;
        capacityMapping[1] = 1024 * 1024 * 1024 * 1024;
        capacityMapping[2] = 1024 * 1024 * 1024 * 1024 * 2;
        capacityMapping[4] = 1024 * 1024 * 1024 * 1024 * 4;
        capacityMapping[8] = 1024 * 1024 * 1024 * 1024 * 8;
        capacityMapping[12] = 1024 * 1024 * 1024 * 1024 * 12;
        validatorBond = ValidatorBond;
		//one percentage
        nodeBond = NodeBond;
    }
    
    function setOwner(address _owner) public {
        require(msg.sender == owner);
        owner = _owner;
    }
    
    function addAdmin(address admin, uint256 role) public {
        require(msg.sender == owner);
        admins[admin] = role;
    }

    function removeAdmin(address admin) public {
        require(msg.sender == owner);
        admins[admin] = 0;
    }
    
    function setCapacity(uint256 weight, uint256 size) public {
        require(msg.sender == owner || admins[msg.sender] == 1);
        capacityMapping[weight] = size;
    }

    function registerCenterNode(uint256 centerNodeId, string peer) public {
        require(msg.sender == owner || admins[msg.sender] == 2);
        
        centerNodePeerMap[centerNodeId] = peer;
        if (!haveUint256(centerNodeIdList, centerNodeId)) {
            centerNodeIdList.push(centerNodeId);
        }
    }
    
    function removeCenterNode(uint256 centerNodeId) public {
        require(msg.sender == owner || admins[msg.sender] == 2);
        
        delete centerNodePeerMap[centerNodeId];
        uint len = centerNodeIdList.length;
        for (uint i = len; i > 0; i--) {
            if (centerNodeIdList[i - 1] == centerNodeId) {
                centerNodeIdList[i - 1] = centerNodeIdList[len - 1];
                delete centerNodeIdList[len - 1];
                centerNodeIdList.length--;
                break;
            }
        }
    }
    
    function getCenterNodePeerList() public view returns (uint256[] memory idList, string[] memory peerList) {
        idList = new uint256[](centerNodeIdList.length);
        peerList = new string[](centerNodeIdList.length);
        for (uint256 i = 0; i < centerNodeIdList.length; i++) {
            idList[i] = centerNodeIdList[i];
            peerList[i] = centerNodePeerMap[centerNodeIdList[i]];
        }
        return (idList, peerList);
    }
    
    function registerSuperNode(address scsId, address beneficiary) public payable returns (bool) {

        require(msg.sender == owner || admins[msg.sender] == 1);
        require(superNodeMapping[scsId].status == 0);
        require(msg.value >= validatorBond * 10 ** 18);
        superNodeList.push(scsId);

        superNodeMapping[scsId].beneficiary = beneficiary;
        superNodeMapping[scsId].status = 1;
		superNodeMapping[scsId].bond = msg.value;
        return true;
    }
    
	function transferSuperNodeBeneficiary(address scsId,address beneficiary) public returns (bool) {
        //only can withdraw when active
        require(msg.sender == superNodeMapping[scsId].beneficiary);
        
        if (superNodeMapping[scsId].status == 1 && msg.sender == superNodeMapping[scsId].beneficiary) {
            superNodeMapping[scsId].beneficiary = beneficiary;
            return true;
        }
		return false;
    }
    
    function getSuperNodeList() public view returns (address[] memory scsidList, address[] memory beneficiaryList) {
        scsidList = new address[](superNodeList.length);
        beneficiaryList = new address[](superNodeList.length);
        
        for (uint256 i = 0; i < superNodeList.length; i++) {
            beneficiaryList[i] = superNodeMapping[superNodeList[i]].beneficiary;
            scsidList[i] = superNodeList[i];
        }
        
        return (scsidList, beneficiaryList);
    }

    // withdrawRequest for SuperNode
    function withdrawSuperNodeRequest(address scsId) public returns (bool) {
        //only can withdraw when active
        require(msg.sender == owner || admins[msg.sender] == 1);
        require(superNodeMapping[scsId].status == 1);

		superNodeMapping[scsId].withdrawSuperNodeMap[superNodeMapping[scsId].beneficiary].withdrawBlock = block.number + 300000;
		superNodeMapping[scsId].withdrawSuperNodeMap[superNodeMapping[scsId].beneficiary].bond += superNodeMapping[scsId].bond;
        superNodeMapping[scsId].status = 2;
        superNodeMapping[scsId].bond = 0;

        return true;
    }
    
    // withdrawRequest for SuperNode
    function withdrawSuperNode(address scsId) public returns (bool){
        //only can withdraw when active
        if (superNodeMapping[scsId].withdrawSuperNodeMap[msg.sender].withdrawBlock < block.number && superNodeMapping[scsId].withdrawSuperNodeMap[msg.sender].bond > 0) {
            msg.sender.transfer(superNodeMapping[scsId].withdrawSuperNodeMap[msg.sender].bond);
            superNodeMapping[scsId].withdrawSuperNodeMap[msg.sender].bond = 0;
            delete superNodeMapping[scsId].withdrawSuperNodeMap[msg.sender];
			return true;
        }
		return false;
    }
	
    function transferSuperNode(address scsId,address beneficiary) public payable {
        require(msg.sender == owner || admins[msg.sender] == 1);
        require(msg.value >= validatorBond * 10 ** 18);
        require(superNodeMapping[scsId].status == 2);
        
        superNodeMapping[scsId].status = 1;
        superNodeMapping[scsId].bond = msg.value;
        if (superNodeMapping[scsId].withdrawSuperNodeMap[superNodeMapping[scsId].beneficiary].withdrawBlock > block.number) {
            superNodeMapping[scsId].withdrawSuperNodeMap[superNodeMapping[scsId].beneficiary].withdrawBlock = block.number;
        }
        superNodeMapping[scsId].beneficiary = beneficiary;
		return;
    }
    
    function setMinerNodePeer(string peer) public {
        require(nodeMapping[msg.sender].status == 1);
        minerNodePeerMap[msg.sender] = peer;
    }
    
    function registerMinerNodeMultiple(address[] mScsIdList, address[] beneficiaryList, uint256[] weightList, address[] scsIdList) public payable {
        require(mScsIdList.length >= beneficiaryList.length);
        require(beneficiaryList.length >= weightList.length);
        require(weightList.length >= scsIdList.length);
        uint256 weightSum = 0;
        for (uint256 i = 0; i < weightList.length; i++) {
            weightSum += weightList[i];
        }
        require(msg.value >= nodeBond * weightSum * 10 ** 18);
        
        for (i = 0; i < mScsIdList.length; i++) {
            registerMinerNode(mScsIdList[i], beneficiaryList[i], weightList[i], scsIdList[i]);
        }
    }

    function registerMinerNode(address mScsId, address beneficiary, uint256 weight, address scsId) public payable returns (bool) {
        require(msg.value >= nodeBond * weight * 10 ** 18);
        addNode(mScsId, beneficiary, weight, scsId, 0, msg.sender);
        minerNodeCount++;
        return true;
    }

    function addNode(address mScsId, address beneficiary, uint256 weight, address scsId, uint isBonded, address sender) private {
        require(superNodeMapping[scsId].status == 1);
        require(nodeMapping[mScsId].sender == 0);
        require(capacityMapping[weight] > 0);

		MinerNode memory nodeTemp;
        nodeTemp.beneficiary = beneficiary;
        nodeTemp.sender = msg.sender;
        nodeTemp.size = capacityMapping[weight];
        nodeTemp.bond = nodeBond * weight * 10 ** 18;
		nodeTemp.status = 1;
		nodeTemp.weight = weight;
		nodeTemp.scsId = scsId;
		nodeTemp.withdrawBlock = 2 ** 256 - 1;

		nodeMapping[mScsId] = nodeTemp;
		minerNodeList.push(mScsId);
		
		superNodeMapping[scsId].minerNodeCount++;
		superNodeMapping[scsId].minerNodeList.push(mScsId);
		superNodeMapping[scsId].size = superNodeMapping[scsId].size + weight;
    }
    
    function transferMinerNodeBeneficiary(address mScsId,address beneficiary) public {
        require(msg.sender == nodeMapping[mScsId].beneficiary);
        require(nodeMapping[mScsId].status == 1);
        
        nodeMapping[mScsId].beneficiary = beneficiary;
    }
    
    function isMinerNode(address addr) public view returns (bool) {
        if (nodeMapping[addr].status != 1) {
            return false;
        }
        return true;
    }
    
    function getMinerNodeList() public view returns (address[] memory mScsIdList, uint256[] memory weightList, address[] memory beneficiaryList, address[] memory scsidList) {
        uint256 j = 0;
        for (uint256 i = 0; i < minerNodeList.length; i++) {
            address nodeAddr = minerNodeList[i];
            if (nodeMapping[nodeAddr].status == 1) {
                addressArr.push(nodeAddr);
                uint256Arr.push(nodeMapping[nodeAddr].weight);
                addressArr1.push(nodeMapping[nodeAddr].beneficiary);
                addressArr2.push(nodeMapping[nodeAddr].scsId);
            }
        }
        
        mScsIdList = addressArr;
        weightList = uint256Arr;
        beneficiaryList = addressArr1;
        scsidList = addressArr2;
        return (mScsIdList, weightList, beneficiaryList, scsidList);
    }
    
    function transferFileIdList(address oldId, address newId) public returns (bool) {
        require(msg.sender == owner || admins[msg.sender] == 1);
        
        bool resp = false;
        uint256 maxNum = 100;
        if (maxNum > myFileList[oldId].length) {
            maxNum = myFileList[oldId].length;
            resp = true;
        }
        for (uint256 i = myFileList[oldId].length; i > myFileList[oldId].length - maxNum; i--) {
            myFileList[newId].push(myFileList[oldId][i - 1]);
            uint256 len = fileMapping[myFileList[oldId][i - 1]].mScsIdList.length;
            for (uint256 j = 0; j < len; j++) {
                if (fileMapping[myFileList[oldId][i - 1]].mScsIdList[j] == oldId) {
                    fileMapping[myFileList[oldId][i - 1]].mScsIdList[j] = newId;
                    break;
                }
            }
            
            len = fileMapping[myFileList[oldId][i - 1]].succSyncMScsIdList.length;
            for (j = len; j > 0; j--) {
                if (fileMapping[myFileList[oldId][i - 1]].succSyncMScsIdList[j-1] == oldId) {
                    fileMapping[myFileList[oldId][i - 1]].succSyncMScsIdList[j-1] = fileMapping[myFileList[oldId][i - 1]].succSyncMScsIdList[len - 1];
                    delete fileMapping[myFileList[oldId][i - 1]].succSyncMScsIdList[len - 1];
                    fileMapping[myFileList[oldId][i - 1]].succSyncMScsIdList.length--;
                    break;
                }
            }
        }
        myFileList[oldId].length -= maxNum;
        return resp;
    }
	
    function withdrawMinerNodeRequest(address mScsId) public returns (bool) {
        require(msg.sender == owner || admins[msg.sender] == 1);
		require(nodeMapping[mScsId].status == 1);
		
		nodeMapping[mScsId].withdrawBlock = block.number + 120000;
		nodeMapping[mScsId].status = 2;
		
        return true;
    }
	
	function withdrawMinerNode(address mScsId) public returns (bool) {
        require(msg.sender == nodeMapping[mScsId].beneficiary || msg.sender == nodeMapping[mScsId].sender || msg.sender == mScsId);
		require(nodeMapping[mScsId].withdrawBlock < block.number && nodeMapping[mScsId].status == 2);
		require(myFileList[mScsId].length == 0);
		
        nodeMapping[mScsId].beneficiary.transfer(nodeMapping[mScsId].bond);
		minerNodeCount--;
		removeMinerNodeArray(mScsId);
		delete nodeMapping[mScsId];
        delete minerNodePeerMap[mScsId];
        return true;
    }
	
	function removeMinerNode(address mScsId, uint256 percent) public returns (bool) {
        require(msg.sender == owner || admins[msg.sender] == 1);
        require(percent >= 0 && percent <= 100);
        require(myFileList[mScsId].length == 0);
		require(nodeMapping[mScsId].sender != 0);
		
		owner.transfer(nodeMapping[mScsId].bond*percent/100);
        nodeMapping[mScsId].beneficiary.transfer(nodeMapping[mScsId].bond*(100-percent)/100);
		minerNodeCount--;
		removeMinerNodeArray(mScsId);
		delete nodeMapping[mScsId];
        delete minerNodePeerMap[mScsId];
        return true;
    }
	
    function registerUser() public {
        require(userMap[msg.sender] == address(0));
        
        uint8 index = 0;
        uint256 a = uint256(superNodeList[0]) ^ uint256(msg.sender);
        uint256 b;
        for (uint8 i = 1; i < superNodeList.length; i++) {
            b = uint256(superNodeList[i]) ^ uint256(msg.sender);
            if (b < a) {
                index = i;
                a = b;
            }
        }
        userMap[msg.sender] = superNodeList[index];
    }
    
	function getMinerNodeListByUserAddr(address user,uint256 size) public view returns (address[]) {
	    uint256 j = 0;
	    for (uint256 i = 0; i < superNodeMapping[userMap[user]].minerNodeList.length; i++) {
	        address minerNodeAddr = superNodeMapping[userMap[user]].minerNodeList[i];
	        if (nodeMapping[minerNodeAddr].size >= size && nodeMapping[minerNodeAddr].status == 1) {
                addressArr.push(minerNodeAddr);
            }
	    }
	    return addressArr;
    }
    
    function judgeNodeSize(address[] addrList, uint256 size) public view returns (bool) {
        for (uint256 i = 0; i < addrList.length; i++) {
	        if (nodeMapping[addrList[i]].size < size || nodeMapping[addrList[i]].status != 1) {
                return false;
            }
	    }
	    return true;
    }

    function addFile(string fileHash, string fileName, uint256 fileSize, address fileOwner, address[] mScsIdList, uint256 centerNodeId) public returns (uint256) {
        require(msg.sender == owner || admins[msg.sender] == 2);
        require(mScsIdList.length == 5);
        uint256 fileId = fileIdNum;

        File memory aFile;
        aFile.fileHash = fileHash;
        aFile.fileName = fileName;
        aFile.fileSize = fileSize;
        aFile.fileOwner = fileOwner;
        aFile.status = 0;
        aFile.mScsIdList = mScsIdList;
        aFile.centerNodeId = centerNodeId;

        fileList.push(fileId);
        fileMapping[fileId] = aFile;
	
        myFileList[fileOwner].push(fileId);
        for (uint i = 0; i < mScsIdList.length; i++) {
            myFileList[mScsIdList[i]].push(fileId);
            require(nodeMapping[mScsIdList[i]].size >= fileSize);
            require(nodeMapping[mScsIdList[i]].scsId == userMap[fileOwner]);
            require(nodeMapping[mScsIdList[i]].status == 1);
            nodeMapping[mScsIdList[i]].size -= fileSize;
        }
        fileIdNum++;
        fileCount = fileList.length;
        return (fileId);
    }
    
    function succSyncFile(uint256 fileId) public {
        require(haveAddress(fileMapping[fileId].mScsIdList, msg.sender));
        require(!haveAddress(fileMapping[fileId].succSyncMScsIdList, msg.sender));
        
        fileMapping[fileId].succSyncMScsIdList.push(msg.sender);
        if (fileMapping[fileId].succSyncMScsIdList.length > fileMapping[fileId].mScsIdList.length / 2) {
            fileMapping[fileId].status = 1;
        }
    }

    function removeFile(uint256 fileId) public returns (bool) {
        require(msg.sender == fileMapping[fileId].fileOwner || msg.sender == owner || admins[msg.sender] == 2);
        uint256[] myList = myFileList[fileMapping[fileId].fileOwner];
		uint len = myList.length;
        for (uint i = len; i > 0; i--) {
            if (myList[i - 1] == fileId) {
                myList[i - 1] = myList[len - 1];
                delete myList[len - 1];
                myList.length--;
                break;
            }
        }
		myFileList[fileMapping[fileId].fileOwner] = myList;
		
		for (i = 0; i < fileMapping[fileId].mScsIdList.length; i++) {
		    address mScsId = fileMapping[fileId].mScsIdList[i];
		    myList = myFileList[mScsId];
		    len = myList.length;
            for (uint j = myList.length; j > 0; j--) {
                if (myList[j - 1] == fileId) {
                    myList[j - 1] = myList[len - 1];
                    delete myList[len - 1];
                    myList.length--;
                    break;
                }
            }
            myFileList[mScsId] = myList;
            nodeMapping[mScsId].size += fileMapping[fileId].fileSize;
        }
        delete fileMapping[fileId];
        removeFileListArray(fileId);
		fileCount--;
        return true;
    }
    
    function getUserFileList(address addr) public view returns (uint256[] memory fileIdList, string[] memory fileNameList, string[] memory fileHashList, uint256[] memory statusList) {
        fileIdList = myFileList[addr];
        fileNameList = new string[](fileIdList.length);
        fileHashList = new string[](fileIdList.length);
        statusList = new uint256[](fileIdList.length);
        for (uint256 i = 0; i < fileIdList.length; i++) {
	        fileNameList[i] = fileMapping[fileIdList[i]].fileName;
	        fileHashList[i] = fileMapping[fileIdList[i]].fileHash;
	        statusList[i] = fileMapping[fileIdList[i]].status;
	    }
	    return (fileIdList, fileNameList, fileHashList, statusList);
    }
    
    function getFileListByStatus(uint256 status) public view returns (uint256[] memory fileIdList, string[] memory fileHashList, address[] memory fileOwnerList) {
        for (uint256 i = 0; i < fileList.length; i++) {
            uint256 fileId = fileList[i];
            if (fileMapping[fileId].status == status) {
                uint256Arr.push(fileId);
                stringArr.push(fileMapping[fileId].fileHash);
                addressArr.push(fileMapping[fileId].fileOwner);
            }
	    }
	    fileIdList = uint256Arr;
	    fileHashList = stringArr;
	    fileOwnerList = addressArr;
	    return (fileIdList, fileHashList, fileOwnerList);
    }
    
    function getMinerNodeFileList(address addr) public view returns (uint256[] memory fileIdList, string[] memory fileHashList, bool[] syncStatusList) {
        fileIdList = myFileList[addr];
        fileHashList = new string[](fileIdList.length);
        syncStatusList = new bool[](fileIdList.length);
        
        for (uint256 i = 0; i < fileIdList.length; i++) {
	        fileHashList[i] = fileMapping[fileIdList[i]].fileHash;
	        syncStatusList[i] = haveAddress(fileMapping[fileIdList[i]].succSyncMScsIdList, addr);
	    }
	    return (fileIdList, fileHashList, syncStatusList);
    }
    
    function getPeerListByFileId(uint256 id) public view returns (string[]) {
        uint256 len = fileMapping[id].mScsIdList.length;
        string[] memory peerList = new string[](len + 1);
        for (uint256 i = 0; i < len; i++) {
	        peerList[i] = minerNodePeerMap[fileMapping[id].mScsIdList[i]];
	    }
        peerList[len] = centerNodePeerMap[fileMapping[id].centerNodeId];
	    return peerList;
    }
    
    function getNodePeerListByFileId(uint256 fileId) public view returns (string[]) {
        address[] mScsIdList = fileMapping[fileId].mScsIdList;
        string[] memory nodePeerList = new string[](mScsIdList.length);
        
        for (uint256 i = 0; i < mScsIdList.length; i++) {
	        nodePeerList[i] = minerNodePeerMap[mScsIdList[i]];
	    }
	    return nodePeerList;
    }

    function compareStringsbyBytes(string s1, string s2) private pure returns (bool) {
        bytes memory s1bytes = bytes(s1);
        bytes memory s2bytes = bytes(s2);
        if (s1bytes.length != s2bytes.length) {
            return false;
        }
        else {
            for (uint i = 0; i < s1bytes.length; i++) {
                if (s1bytes[i] != s2bytes[i])
                    return false;
            }
            return true;
        }
    }

    function removeSuperNodeArray(address key) private {
        uint len = superNodeList.length;
        for (uint i = len; i > 0; i--) {
            if (superNodeList[i - 1] == key) {
                superNodeList[i - 1] = superNodeList[len - 1];
                delete superNodeList[len - 1];
                superNodeList.length--;
                break;
            }
        }
    }
	
	function removeMinerNodeArray(address key) private {
        uint len = minerNodeList.length;
        for (uint i = len; i > 0; i--) {
            if (minerNodeList[i - 1] == key) {
                minerNodeList[i - 1] = minerNodeList[len - 1];
                delete minerNodeList[len - 1];
                minerNodeList.length--;
                break;
            }
        }
        
        len = superNodeMapping[nodeMapping[key].scsId].minerNodeList.length;
        for (i = len; i > 0; i--) {
            if (superNodeMapping[nodeMapping[key].scsId].minerNodeList[i - 1] == key) {
                superNodeMapping[nodeMapping[key].scsId].minerNodeList[i - 1] = superNodeMapping[nodeMapping[key].scsId].minerNodeList[len - 1];
                delete superNodeMapping[nodeMapping[key].scsId].minerNodeList[len - 1];
                superNodeMapping[nodeMapping[key].scsId].minerNodeList.length--;
                break;
            }
        }
        
        superNodeMapping[nodeMapping[key].scsId].minerNodeCount--;
		superNodeMapping[nodeMapping[key].scsId].size -= nodeMapping[key].weight;
    }

    function removeFileListArray(uint256 key) private {
        uint len = fileList.length;
        for (uint i = len; i > 0; i--) {
            if (fileList[i - 1] == key) {
                fileList[i - 1] = fileList[len - 1];
                delete fileList[len - 1];
                fileList.length--;
                break;
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
    
    function haveUint256(uint256[] addrs, uint256 addr) private returns (bool) {
        uint256 i;
        for (i = 0; i < addrs.length; i++) {
            if(addrs[i] == addr) {
                return true;
            }
        }
        return false;
    }
}