---
name: chatgpt-remote-mcp
description: Set up or troubleshoot ChatGPT browser access to this Windows PC through the AI Folder Remote Desktop Commander MCP connector. Use for local coding, terminal execution, and deployment through ChatGPT.
metadata:
  short-description: ChatGPT 원격 PC MCP 연결
---

# ChatGPT Remote MCP

Use this skill when the user wants ChatGPT in the browser to work on a Windows PC's local projects through MCP.

## Required components

- A locally running Desktop Commander Remote agent.
- A ChatGPT developer-mode plugin configured with `https://mcp.desktopcommander.app/mcp` and OAuth.
- The `AI Folder Remote` plugin enabled in the ChatGPT conversation.

The local agent must remain running. It pairs the PC with Desktop Commander Remote; SSH and port forwarding are not required.

## Setup or repair

1. Start the local agent with `npx @wonderwhy-er/desktop-commander@latest remote`, or a batch launcher that runs that command. Do not publish the pairing URL or one-time device code.
2. In ChatGPT, enable Developer Mode if needed, then create or inspect the plugin. Use the endpoint above and OAuth.
3. Let the user complete login/device verification and obtain confirmation immediately before any final persistent OAuth authorization.
4. Refresh plugin details and verify Desktop Commander actions load. Do not run a write or deployment test merely to validate the connection.

## Using ChatGPT

Ask the user to enable the plugin in a new ChatGPT conversation. ChatGPT may otherwise use its isolated `/workspace` sandbox rather than the PC. Make the remote tool explicit, for example:

```text
AI Folder Remote(Desktop Commander)를 사용해서 C:\Users\<user>\Documents\ai를 확인해줘.
ChatGPT 작업공간(/workspace)은 사용하지 마.
```

For code changes or releases, have ChatGPT present the target files and commands first and wait for user approval before destructive actions, package publishing, deployments, or sensitive-data transmission.

## Safety and scope

Desktop Commander Remote is a third-party service that can act with the local user's access while the agent is running. Keep work scoped to the requested directory. Do not disable security controls or configure SSH/port forwarding unless the user specifically asks.

Close the local agent when remote access is no longer needed.
