//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IPinkAntiBot{
  function setTokenOwner(address owner) external;

  function onPreTransferCheck(
    address to,
    address from,
    uint256 amount
  ) external;
}