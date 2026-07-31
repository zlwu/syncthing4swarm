# Swarm deployment-control directory example

This directory is a public template only. Do not copy real homelab files, IP addresses, domains, node names, credentials, or `.env` files into this repository.

## Intended private layout

```text
/opt/swarm-stacks/
├── .env                 # private, synced between trusted managers only
├── deploy-stack.sh      # private wrapper
└── <stack>/
    ├── stack.yml
    └── .env             # private, optional
```

The synchronized directory contains deployment control files only. Application data remains in each node's local `/opt/stacks` path. Stack bind mounts should use absolute `/opt/stacks/...` paths so deployment can be initiated from any manager without changing the task's data node.

## Public examples

- `.env.example` contains names only.
- `stack.yml.example` uses placeholders only.
- The real `.env` and production stack files must stay outside this public repository.
