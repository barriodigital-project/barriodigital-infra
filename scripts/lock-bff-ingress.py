#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys


def aws_json(*arguments):
    result = subprocess.run(
        ["aws", *arguments, "--output", "json"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def revoke(group_id, permission, apply):
    print(f"Remove direct BFF ingress source: {json.dumps(permission)}")
    if apply:
        subprocess.run(
            [
                "aws",
                "ec2",
                "revoke-security-group-ingress",
                "--group-id",
                group_id,
                "--ip-permissions",
                json.dumps([permission]),
            ],
            check=True,
        )


def main():
    parser = argparse.ArgumentParser(
        description="Restrict the Swarm BFF port to the internal NLB security group."
    )
    parser.add_argument("--region", required=True)
    parser.add_argument("--swarm-security-group-id", required=True)
    parser.add_argument("--nlb-security-group-id", required=True)
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Revoke direct ingress rules; without this flag only inspect them.",
    )
    arguments = parser.parse_args()

    response = aws_json(
        "ec2",
        "describe-security-groups",
        "--region",
        arguments.region,
        "--group-ids",
        arguments.swarm_security_group_id,
    )
    groups = response.get("SecurityGroups", [])
    if len(groups) != 1:
        raise RuntimeError("The specified Swarm security group was not found.")

    unauthorized = []
    broad = []
    for rule in groups[0].get("IpPermissions", []):
        protocol = str(rule.get("IpProtocol"))
        start = rule.get("FromPort")
        end = rule.get("ToPort")
        matches_port = protocol == "-1" or (
            protocol in {"tcp", "6"}
            and start is not None
            and end is not None
            and start <= arguments.port <= end
        )
        if not matches_port:
            continue

        sources = (
            ("IpRanges", "CidrIp"),
            ("Ipv6Ranges", "CidrIpv6"),
            ("PrefixListIds", "PrefixListId"),
            ("UserIdGroupPairs", "GroupId"),
        )
        non_nlb_sources = [
            (collection, source)
            for collection, source_key in sources
            for source in rule.get(collection, [])
            if not (collection == "UserIdGroupPairs"
                    and source.get(source_key) == arguments.nlb_security_group_id)
        ]
        if not non_nlb_sources:
            continue

        if protocol == "-1" or start != arguments.port or end != arguments.port:
            broad.append(rule)
            continue

        for collection, source in non_nlb_sources:
            permission = {
                "IpProtocol": rule["IpProtocol"],
                "FromPort": rule["FromPort"],
                "ToPort": rule["ToPort"],
                collection: [source],
            }
            unauthorized.append(permission)

    if broad:
        print(
            "ERROR: broad BFF ingress rules also cover other traffic; narrow them "
            "manually before locking the BFF port.",
            file=sys.stderr,
        )
        for rule in broad:
            print(json.dumps(rule), file=sys.stderr)
        return 2

    if not unauthorized:
        print("BFF ingress is restricted to the configured NLB security group.")
        return 0

    for permission in unauthorized:
        revoke(arguments.swarm_security_group_id, permission, arguments.apply)

    if not arguments.apply:
        print("Inspection only. Add --apply to revoke the listed ingress rules.")
        return 1

    print("Direct BFF ingress rules were revoked.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (subprocess.CalledProcessError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
