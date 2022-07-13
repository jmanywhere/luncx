from brownie import LuncxToken, IterableMapping, accounts, chain, interface


def main():
    owner = accounts.load("dep")
    IterableMapping.deploy({"from": owner}, publish_source=True)
    token = LuncxToken.deploy(
        "0x3d04e17305A233597e0585E226C3E9174C0ACF4E",
        "0x8EFDb3b642eb2a20607ffe0A56CFefF6a95Df002",
        {"from": owner},
        publish_source=True,
    )
