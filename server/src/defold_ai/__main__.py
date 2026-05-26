"""Entry point: `uv run defold-ai`."""

from defold_ai.server import build_server


def main() -> None:
    server = build_server()
    server.run()


if __name__ == "__main__":
    main()
