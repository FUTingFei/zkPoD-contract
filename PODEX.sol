pragma experimental ABIEncoderV2;

contract PODEX {

    struct Bulletin {
        address owner;
        uint64 size;
        uint64 s;
        uint64 n;
        uint256 sigma_mkl_root;
        uint256 vrf_meta_digest;
        uint256 pledge_value;
        uint256 unDepositAt;
        BltType blt_type;
        DepositStatus status;
    }

    struct Deposit {
        uint256 value;
        uint256 unDepositAt;
        DepositStatus status;
    }

    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct PlainRangeProof1ForClaim {
        bytes32 seed0;
        PlainRangeReceipt1ForClaim receipt;
        Signature receiptSig;
    }

    struct SessionRecord {
        bytes32 seed0;
        PlainRangeReceipt1ForClaim receipt;
        uint256 submitAt;
    }

    struct PlainRangeReceipt1ForClaim {
        uint256 sessionId;
        address from;
        bytes32 seed2;
        bytes32 k_mkl_root;
        uint64 count;
        uint256 price;
        uint256 expireAt;
    }

    struct G1Point {
        uint256 X;
        uint256 Y;
    }

    enum DepositStatus {
        OK,
        CANCELING,
        CANCELED
    }

    enum BltType {
        PLAIN,
        TABLE
    }

    mapping (bytes32 => Bulletin) public bulletins_;

    // B => A => Deposit
    mapping (address => mapping(address => Deposit)) public buyerDeposits_;

    // A => B => SessionId => Receipt
    mapping (address => mapping(address => mapping(uint256 => SessionRecord))) internal sessionRecords_;

    mapping (uint256 => G1Point) public ecc_pub_u1_;


    uint64 public s_ = 9;
    

    // core

    function publish(uint64 _size, uint64 _s, uint64 _n, uint256 _sigma_mkl_root, uint256 _vrf_meta_digest, uint256 _blt_type)
        public
        payable
    {
        bytes32 _bltKey;
        BltType _bltType;
        if (_blt_type == 0) {
            _bltType = BltType.PLAIN;
            _bltKey = keccak256(abi.encodePacked(_size, _s, _n, _sigma_mkl_root));
        } else if (_blt_type == 1) {
            _bltType = BltType.TABLE;
            _bltKey = keccak256(abi.encodePacked(_s, _n, _sigma_mkl_root, _vrf_meta_digest));
        } else {
            revert();
        }
        require(bulletins_[_bltKey].owner != address(0));
        Bulletin memory file = Bulletin({
             owner: msg.sender,
             size: _size,
             s: _s,
             n: _n,
             sigma_mkl_root: _sigma_mkl_root,
             vrf_meta_digest: _vrf_meta_digest,
             pledge_value: msg.value,
             unDepositAt: 0,
             blt_type: _bltType,
             status: DepositStatus.OK
        });
        bulletins_[_bltKey] = file;
    }

    function unPublish(bytes32 _bltKey)
        public
    {
        require(bulletins_[_bltKey].status == DepositStatus.OK);
        bulletins_[_bltKey].status = DepositStatus.CANCELING;
        bulletins_[_bltKey].unDepositAt = now;  
    }

    function buyerDeposit(address _to)
        public
        payable
    {
        buyerDeposits_[msg.sender][_to].value = buyerDeposits_[msg.sender][_to].value + msg.value;
    }

    function buyerUnDeposit(address _to)
        public
    {
        require(buyerDeposits_[msg.sender][_to].status == DepositStatus.OK);
        buyerDeposits_[msg.sender][_to].status = DepositStatus.CANCELING;
        buyerDeposits_[msg.sender][_to].unDepositAt = now;
    }

    function withdraw(bytes32 _bltKey)
        public
    {
        require(bulletins_[_bltKey].owner == msg.sender);
        require(bulletins_[_bltKey].status == DepositStatus.CANCELING);
        require(now - bulletins_[_bltKey].unDepositAt > 7 days);
        // transfer
    }

    function withdraw(address _to)
        public
    {
        require(buyerDeposits_[msg.sender][_to].status == DepositStatus.CANCELING);
        require(now - buyerDeposits_[msg.sender][_to].unDepositAt > 7 days);
        // transfer
    }

    // plain range
    // function submitProof1() public;

    function checkSig1(address addr, PlainRangeReceipt1ForClaim memory r1, Signature memory sig)
        internal
        pure
        returns (bool)
    {
        bytes32 hash = keccak256(abi.encodePacked(r1.sessionId, r1.from, r1.seed2, r1.k_mkl_root, r1.count, r1.price, r1.expireAt));
        return addr == ecrecover(hash, sig.v, sig.r, sig.s);
    }

    // uint256 seed0, 
    // uint256 sessionId,
    // address from,
    // bytes32 seed2,
    // bytes32 k_mkl_root,
    // uint64 count,
    // uint256 price,
    // uint256 expireAt,
    // uint8 v,
    // bytes32 r,
    // bytes32 s,
    function submitProof1WaitClaim
    (
        bytes32 _seed0, 
        uint256 _sessionId,
        address _b,
        bytes32 _seed2,
        bytes32 _k_mkl_root,
        uint64 _count,
        uint256 _price,
        uint256 _expireAt,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        public
    {
        PlainRangeReceipt1ForClaim memory _receipt = PlainRangeReceipt1ForClaim({
            sessionId: _sessionId,
            from: _b,
            seed2: _seed2,
            k_mkl_root: _k_mkl_root,
            count: _count,
            price: _price,
            expireAt: _expireAt
        });

        Signature memory _sig = Signature({
            v: _v,
            r: _r,
            s: _s 
        });

        // require(checkSig1(_b, _receipt, _sig));
        // require(now < _expireAt);
        require(sessionRecords_[msg.sender][_b][_sessionId].receipt.from == address(0));
        sessionRecords_[msg.sender][_b][_sessionId] = SessionRecord({
            seed0: _seed0,
            receipt: _receipt,
            submitAt: now
        });
    }

    // function submitProof1WaitClaim(PlainRangeProof1ForClaim memory proof1)
    //     public
    // {
    //     address _from = proof1.receipt.from;
    //     uint256 _sessionId = proof1.receipt.sessionId;
    //     require(checkSig1(_from, proof1.receipt, proof1.receiptSig));
    //     require(now < proof1.receipt.expireAt);
    //     require(sessionRecords_[msg.sender][proof1.receipt.from][_sessionId].receipt.from == address(0));
    //     sessionRecords_[msg.sender][_from][_sessionId] = SessionRecord({
    //         seed0: proof1.seed0,
    //         receipt: proof1.receipt,
    //         submitAt: now
    //     });
    // }

    function claim(address _a, uint256 _sessionId, uint64 _i, uint64 _j, uint256 _tx, uint256 _ty, bytes32[] memory _mkl_path)
        public
    {
        // loadReceipt
        SessionRecord memory _sessionRecord = sessionRecords_[_a][msg.sender][_sessionId];
        // convert tij to big endian LogBytes32

        // verify mkl path
        // TODO: think about overflow here
        uint64 _index = _i*s_+_j;
        bytes32 _x = convertToBE(bytes32(_tx));
        bytes32 _y = convertToBE(bytes32(_ty));
        require(verifyPath(_x, _y, _index, _sessionRecord.receipt.count*s_, _sessionRecord.receipt.k_mkl_root, _mkl_path), "invalid mkl proof");
        // derive k
        uint256 _v = chain(_sessionRecord.seed0, _index);
        // calc u^v
        G1Point memory _check = scalarMul(ecc_pub_u1_[_j].X, ecc_pub_u1_[_j].Y, _v);
        emit LogUint256(_check.X);
        emit LogUint256(_check.Y);
        require(_check.X != _tx || _check.Y != _ty, "invalid claim");
        // transfer
    }


    // internal or helper
    function hashOfTwoSha3(bytes32 _x, bytes32 _y)
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_x, _y));
    }

    function hashOfTwoSha3(bytes32 _x, uint64 _y)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_x, _y));
    }

    function hashOfTwoSha256(bytes32 _x, bytes32 _y)
        public
        pure
        returns (bytes32)
    {
        return sha256(abi.encodePacked(_x, _y));
    }

    function log2ub(uint256 _n)
        public
        view
        returns (uint256)   
    {
        if (_n == 1) return 0;
        if (_n % 2 != 0) _n++;
        return 1 + log2ub(_n / 2);
    }

    // // for debug
    // event LogVerifyPath(uint256 _i, uint64 _pos, bytes32 _value);
    // event LogBeforeBytes32(bytes32 _mkl_path_i, bytes32 _value);
    event LogBytes32(bytes32 _b);
    event LogBytes(bytes _b);
    event LogUint256(uint256 _i);

    function chain(bytes32 seed, uint64 index)
        public
        returns (uint256)
    {
        bytes32 _ret = hashOfTwoSha3(seed, index);
        emit LogBytes32(_ret);

        bytes memory shasum = new bytes(32);
        uint j;
        for (j=0; j<32; j++) {
            shasum[j] = _ret[j];
        }
        emit LogBytes(shasum);

        shasum[0] = byte(uint8(shasum[0]) & 63);
        if(shasum[0] > 0x30) {
            shasum[0] = byte(uint8(shasum[0]) & 31);
        }
        
        bytes32 revhash;
        assembly {
            revhash := mload(add(shasum, 32))
        }
        return uint256(revhash);
    }

    function verifyPath(bytes32 _x, bytes32 _y, uint64 _ij, uint64 _ns, bytes32 _root, bytes32[] memory _mkl_path)
        public
        // view
        returns (bool)
    {
        bytes32 _value_b = hashOfTwoSha3(_x, _y);
        uint256 _depth = log2ub(_ns);
        if (_mkl_path.length != _depth) {
            return false;
        }
        bytes32 _value = _value_b;

        uint64 _pos = _ij;
        for (uint256 _i = 0; _i < _depth; _i++) {
            // emit LogBeforeBytes32(_mkl_path[_i], _value);
            if (_pos % 2 != 0) {
                _value = hashOfTwoSha256(_mkl_path[_i], _value);
            } else {
                _value = hashOfTwoSha256(_value, _mkl_path[_i]);
            }
            _pos /= 2;
            // emit LogVerifyPath(_i, _pos, _value);
        }
        return (_value == _root);
    }

    function convertToBE(bytes32 _in)
        public
        view
        returns (bytes32)
    {
        bytes memory _bytes = new bytes(32);
        for (uint256 j = 0; j < 32; j++) {
            _bytes[j] = _in[31-j];
        }
        bytes32 _out;
        assembly {
            _out := mload(add(_bytes, 32))
        }
        return _out;
    }

    function convertToBE2(uint256 _in)
        public
        view
        returns (bytes32)
    {
        bytes32 _bin = bytes32(_in);
        bytes memory _bytes = new bytes(32);
        for (uint256 j = 0; j < 32; j++) {
            _bytes[j] = _bin[31-j];
        }
        bytes32 _out;
        assembly {
            _out := mload(add(_bytes, 32))
        }
        return _out;
    }

    function scalarMul(uint256 _x, uint256 _y, uint256 _s)
        internal
        view
        returns (G1Point memory r)
    {
        uint[3] memory input;
        input[0] = _x;
        input[1] = _y;
        input[2] = _s;
        bool success;
        assembly {
            success := staticcall(sub(gas, 2000), 7, input, 0x80, r, 0x60)
            // Use "invalid" to make gas estimation work
            switch success case 0 { invalid() }
        }
        require (success);
    }

    function submitProof2() public {
    
    }

    function getSessionRecord(address _a, address _b, uint256 _sessionId)
        public
        view
        returns (
            bytes32 seed0,
            bytes32 seed2,
            bytes32 k_mkl_root,
            uint64 count,
            uint256 price,
            uint256 expireAt,
            uint256 submitAt
        )
    {
        SessionRecord memory _sessionRecord = sessionRecords_[_a][_b][_sessionId];
        seed0 = _sessionRecord.seed0;
        seed2 = _sessionRecord.receipt.seed2;
        k_mkl_root = _sessionRecord.receipt.k_mkl_root;
        count = _sessionRecord.receipt.count;
        price = _sessionRecord.receipt.price;
        expireAt = _sessionRecord.receipt.expireAt;
        submitAt = _sessionRecord.submitAt;
    }

    constructor() public {
        ecc_pub_u1_[0] = G1Point(1,2);
        ecc_pub_u1_[1] = G1Point(3703773065101994655395965342281618899061728682269912479640181914419937900737,1381553616591959742569695122438047644609291220379263254272259030529521113681);
        ecc_pub_u1_[2] = G1Point(21797362884209412546615131605077856700501183410536444612538341641387847500007,7080542245092340998700143047880907169097999696990214549662535633588955108714);
        ecc_pub_u1_[3] = G1Point(21532697142137562349116254148520077213073387297270716924735603363752441699828,17160544929250551222153841234886930646478845098648572254547176931561408378111);
        ecc_pub_u1_[4] = G1Point(21153788652835541544570862567504148310233673148988627424909832914276521661080,14404593217557941108998250914798670727808633710827930583465543120693988990842);
        ecc_pub_u1_[5] = G1Point(2640393578075525862409361269525080993080457285944385479131064261161724932674,4405708151459024101449179983863193388829351619769162523267977900746727051299);
        ecc_pub_u1_[6] = G1Point(7972551752567364852146836157171723144578741293295216305070633740691753325216,1605665667549530074496162176500916179836387412153691649067921375328307583897);
        ecc_pub_u1_[7] = G1Point(18491553233315392497917791564516437063351587113203942677415559944870987733015,12860729462227989853358289651477867684943173185396232004539441766153239199554);
        ecc_pub_u1_[8] = G1Point(3807161381314380913772269402345043816267303240211235621703228400790451786108,10134198336703696056038675509990550447583490347457293005275143717478926208436);
        ecc_pub_u1_[8] = G1Point(16875491829548039670190686133702078189877162158081810891938692723525527011635,17055142778236739778134621677369618060219189423496455602452221834992101370796);
        ecc_pub_u1_[10] = G1Point(18893704954181691319057845074014928747364995691008196613190768621408190701550,17259505777100151142392424930431971083828900618464660517076335414817428698349);
    }

}
