// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract AccidentRegistry {
    struct Record {
        bytes32 pdfHash;
        bytes32 bundleHash;   // hash over all attachment hashes
        uint256 timestamp;
        address submitter;
    }

    mapping(bytes32 => Record) private records;

    event ReportAnchored(
        bytes32 indexed reportId,
        bytes32 pdfHash,
        bytes32 bundleHash,
        uint256 timestamp
    );

    function anchor(bytes32 reportId, bytes32 pdfHash, bytes32 bundleHash) external {
        require(records[reportId].timestamp == 0, "already anchored");
        records[reportId] = Record(pdfHash, bundleHash, block.timestamp, msg.sender);
        emit ReportAnchored(reportId, pdfHash, bundleHash, block.timestamp);
    }

    function getRecord(bytes32 reportId)
        external view returns (bytes32, bytes32, uint256, address)
    {
        Record memory r = records[reportId];
        require(r.timestamp != 0, "not found");
        return (r.pdfHash, r.bundleHash, r.timestamp, r.submitter);
    }

    function verify(bytes32 reportId, bytes32 pdfHash) external view returns (bool) {
        return records[reportId].pdfHash == pdfHash && records[reportId].timestamp != 0;
    }
}
