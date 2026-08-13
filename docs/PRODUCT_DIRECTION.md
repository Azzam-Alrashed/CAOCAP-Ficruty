# CAOCAP Product Direction

CAOCAP is becoming an end-to-end command center for AI agents and computers.

This document describes the target product. Feature-level README files describe
the current implementation and may contain transitional systems that will be
replaced as the new platform is built.

## Product Model

- **Mission Control:** The iOS app is a conversational whiteboard where users
  define missions, observe work, and redirect agents.
- **CoPilot:** CoCaptain or CoStar turns user intent into a visible multi-agent
  workflow. Users request changes conversationally instead of wiring nodes.
- **Orchestrator:** Coordinates tasks, agents, approvals, execution state, and
  results across available computers.
- **Compute Network:** Work can run on user-owned Mac, Linux, and Windows
  computers or CAOCAP-hosted cloud computers.
- **Runner:** Lightweight software on each computer executes agent work, streams
  observable state to Mission Control, and presents an animated agent-bot face.

The agent-bot face is a simple 2D shape with a unique gradient and two dot eyes.
It represents an execution agent's identity and state; it is distinct from the
CoCaptain and CoStar CoPilot characters.

## Core Interaction

**Command → orchestrate → execute → observe → redirect.**

The user does not directly operate every computer. They direct the intelligence
operating them.

## Product Principles

- Keep the canvas primary and make it feel like a whiteboard.
- Author and modify workflows through conversation.
- Keep orchestration visible without requiring manual node editing.
- Let users select workflow elements to ask about or change them.
- Make agent execution observable, including optional live screen streaming.
- Support personal and CAOCAP-hosted computers in the same mission.
- Clearly distinguish implemented behavior from future product direction.

## Current State

The repository currently contains an iOS foundation with a spatial canvas,
CoPilot chat, Command Line, account and subscription systems, and legacy project
infrastructure. The cross-platform Runner, orchestration service, compute
network, cloud computers, and new workflow model are not implemented yet.
