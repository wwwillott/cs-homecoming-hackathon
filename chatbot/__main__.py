"""Run the suggested events prompt once, then delete the session.

    python -m chatbot
"""

from .orbit_agent import OrbitAgent, suggested_prompts
from .prompts import MODEL, REASONING_EFFORT


def main() -> None:
    prompt = suggested_prompts()[0]
    print(f"model: {MODEL}")
    print(f"reasoning: {REASONING_EFFORT}")
    print(f"prompt: {prompt}")
    print("---")
    agent = OrbitAgent()
    try:
        for chunk in agent.send(prompt):
            print(chunk, end="", flush=True)
        print()
        print("---")
        print(f"session: {agent.session_id}")
    finally:
        agent.close()
        print("session deleted")


if __name__ == "__main__":
    main()
