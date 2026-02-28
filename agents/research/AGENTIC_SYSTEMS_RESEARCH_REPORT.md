# Comprehensive Research Report: Agentic AI Systems

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Foundational Concepts](#foundational-concepts)
3. [Agent Loop Patterns](#agent-loop-patterns)
4. [Detailed Examples (20+)](#detailed-examples)
5. [Tool Integration Patterns](#tool-integration-patterns)
6. [Memory Architectures](#memory-architectures)
7. [Orchestration Patterns](#orchestration-patterns)
8. [Prompt Engineering for Agents](#prompt-engineering-for-agents)
9. [Framework Comparison](#framework-comparison)
10. [References](#references)

---

## Executive Summary

Agentic AI systems represent a paradigm shift from static LLM applications to autonomous, goal-directed AI that can plan, reason, and act. This report synthesizes research from academic papers, open-source frameworks, and production implementations to provide a comprehensive guide to building agentic systems.

**Key Findings:**

- The fundamental agent loop is: **Observe → Reason/Plan → Act → Update State → Repeat**
- Most production systems use variations of **ReAct**, **Plan-and-Execute**, or **Reflexion** patterns
- Tool integration is critical—agents are only as capable as their available tools
- Memory (short-term, long-term, episodic) is essential for complex multi-step tasks
- Multi-agent orchestration follows **Manager**, **Decentralized**, or **Blackboard** patterns

---

## Foundational Concepts

### What is an Agent?

An **AI agent** is a system that:

1. Uses an LLM to **manage workflow execution** and make decisions
2. Has access to **tools** to interact with external systems
3. Operates within **guardrails** that define behavior boundaries
4. Can **recognize completion** and proactively correct errors

```
┌─────────────────────────────────────────────────────────────┐
│                        AI AGENT                              │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │    MODEL     │  │    TOOLS     │  │ INSTRUCTIONS │       │
│  │   (LLM)      │  │  (Actions)   │  │ (Guardrails) │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│         ↓                  ↓                  ↓              │
│  ┌──────────────────────────────────────────────────┐       │
│  │              AGENT LOOP                          │       │
│  │  Observe → Reason → Plan → Act → Update State   │       │
│  └──────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### The Core Agent Loop

```python
# Fundamental Agent Loop (Pseudocode)
state = initialize_state(task)
while not state.done:
    # 1. Collect observations
    observations = collect_observations(state)

    # 2. Build context (with memory and retrieval)
    context = build_context(state, observations, memory)

    # 3. LLM decides next action
    action = llm_policy(context, available_tools)

    # 4. Execute the action
    result = execute_action(action)

    # 5. Update state and memory
    state = update_state(state, action, result)
    memory.store(observation=result, action=action)

return state.final_output
```

---

## Agent Loop Patterns

### Pattern 1: ReAct (Reasoning + Acting)

**Source:** [Yao et al., 2022](https://arxiv.org/abs/2210.03629)

**Key Insight:** Interleave reasoning traces with actions, allowing the model to think about what to do, act, observe results, and adjust.

```
┌─────────────────────────────────────────┐
│           ReAct Loop                     │
├─────────────────────────────────────────┤
│  Thought → Action → Observation         │
│      ↑                    │             │
│      └────────────────────┘             │
│           (repeat until done)           │
└─────────────────────────────────────────┘
```

**Canonical Prompt Template:**

```text
Answer the following questions as best you can. You have access to the following tools:

{tools}

Use the following format:

Question: the input question you must answer
Thought: you should always think about what to do
Action: the action to take, should be one of [{tool_names}]
Action Input: the input to the action
Observation: the result of the action
... (this Thought/Action/Action Input/Observation can repeat N times)
Thought: I now know the final answer
Final Answer: the final answer to the original input question

Begin!

Question: {input}
Thought:{agent_scratchpad}
```

**When to Use:**

- Sequential tasks requiring external data
- Question answering with knowledge retrieval
- Tasks requiring iterative exploration

---

### Pattern 2: Plan-and-Execute

**Key Insight:** Separate planning from execution. Create a comprehensive plan first, then execute steps.

```
┌─────────────────────────────────────────┐
│        Plan-and-Execute                  │
├─────────────────────────────────────────┤
│  Phase 1: PLANNING                       │
│  ┌─────────────────────────────────┐    │
│  │ Analyze task → Create step plan │    │
│  └─────────────────────────────────┘    │
│                  ↓                       │
│  Phase 2: EXECUTION                      │
│  ┌─────────────────────────────────┐    │
│  │ Execute Step 1 → Check result   │    │
│  │ Execute Step 2 → Check result   │    │
│  │ ...                             │    │
│  └─────────────────────────────────┘    │
│                  ↓                       │
│  Phase 3: SYNTHESIS                      │
│  ┌─────────────────────────────────┐    │
│  │ Aggregate results → Final answer│    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

**Planner Prompt Example:**

```text
You are a planning agent. Given the user's task, create a detailed step-by-step plan.

For each step, specify:
1. What action to take
2. What tool is needed
3. What the expected output is
4. Dependencies on previous steps

Task: {user_task}

Create a plan in the following format:
Step 1: [Description] - Tool: [tool_name] - Depends on: [none/step N]
Step 2: ...
```

**When to Use:**

- Complex multi-step tasks
- Tasks with clear dependencies between steps
- When you need predictable execution paths

---

### Pattern 3: Reflexion (Self-Refinement)

**Source:** [Shinn et al., 2023](https://arxiv.org/abs/2303.11366)

**Key Insight:** Learn from failures by reflecting on past attempts and storing lessons learned.

```
┌─────────────────────────────────────────┐
│           Reflexion Loop                 │
├─────────────────────────────────────────┤
│  Attempt → Evaluate → Reflect → Store   │
│      ↑                           │      │
│      └───────── Retry ───────────┘      │
└─────────────────────────────────────────┘
```

**Reflection Prompt:**

```text
Task: {task}
Previous Attempt: {attempt}
Result: {result}
Was Successful: {success}

Analyze this attempt:
1. What went wrong?
2. What assumptions were incorrect?
3. What should be done differently next time?

Reflection:
```

---

### Pattern 4: Tree of Thoughts (ToT)

**Key Insight:** Explore multiple reasoning paths in parallel, evaluate them, and select the best.

```
                    Root (Problem)
                   /      |      \
              Path A   Path B   Path C
              /   \      |      /   \
           S1    S2     S3    S4    S5
          (✓)   (✗)    (✓)   (✗)   (✓)
           ↓            ↓           ↓
        Continue     Continue   Continue
```

**When to Use:**

- Problems with multiple valid solution paths
- Creative or open-ended tasks
- When you need to explore alternatives

---

## Detailed Examples

### Example 1: LangChain ReAct Agent

**Framework:** LangChain  
**Pattern:** ReAct  
**Source:** [github.com/langchain-ai/langchain](https://github.com/langchain-ai/langchain)

```python
from langchain.agents import create_react_agent, AgentExecutor
from langchain_openai import ChatOpenAI
from langchain.tools import Tool

# Define tools
tools = [
    Tool(
        name="search",
        func=search_function,
        description="Search the web for current information"
    ),
    Tool(
        name="calculator",
        func=calculator_function,
        description="Perform mathematical calculations"
    )
]

# Create agent
llm = ChatOpenAI(model="gpt-4")
agent = create_react_agent(llm, tools, prompt)
executor = AgentExecutor(agent=agent, tools=tools, verbose=True)

# Run
result = executor.invoke({"input": "What is 15% of the current Bitcoin price?"})
```

**Flow:**

1. User asks question
2. Agent thinks: "I need to find current Bitcoin price"
3. Action: `search("current Bitcoin price")`
4. Observation: "$67,000"
5. Thought: "Now I need to calculate 15% of $67,000"
6. Action: `calculator("67000 * 0.15")`
7. Observation: "$10,050"
8. Final Answer: "15% of the current Bitcoin price is $10,050"

---

### Example 2: LangGraph State Machine Agent

**Framework:** LangGraph  
**Pattern:** Graph-based state machine  
**Source:** [github.com/langchain-ai/langgraph](https://github.com/langchain-ai/langgraph)

```python
from langgraph.graph import StateGraph, END
from typing import TypedDict, Annotated
from langgraph.graph.message import add_messages

class AgentState(TypedDict):
    messages: Annotated[list, add_messages]
    next_step: str

def agent_node(state: AgentState):
    """Call LLM and decide next action"""
    response = llm.invoke(state["messages"])
    return {"messages": [response]}

def tool_node(state: AgentState):
    """Execute tool calls"""
    last_message = state["messages"][-1]
    results = execute_tools(last_message.tool_calls)
    return {"messages": results}

def should_continue(state: AgentState):
    """Route to tools or end"""
    last_message = state["messages"][-1]
    if last_message.tool_calls:
        return "tools"
    return END

# Build graph
workflow = StateGraph(AgentState)
workflow.add_node("agent", agent_node)
workflow.add_node("tools", tool_node)
workflow.set_entry_point("agent")
workflow.add_conditional_edges("agent", should_continue, {"tools": "tools", END: END})
workflow.add_edge("tools", "agent")

graph = workflow.compile()
```

**Key Features:**

- Explicit state management with reducers
- Conditional routing between nodes
- Built-in checkpointing for long-running tasks
- Support for human-in-the-loop patterns

---

### Example 3: AutoGPT Autonomous Agent

**Framework:** AutoGPT  
**Pattern:** Goal-directed autonomous loop  
**Source:** [github.com/Significant-Gravitas/Auto-GPT](https://github.com/Significant-Gravitas/Auto-GPT)

```
┌────────────────────────────────────────────────────────────┐
│                    AutoGPT Architecture                     │
├────────────────────────────────────────────────────────────┤
│                                                             │
│  User Input: Name + Goals (up to 5)                        │
│         ↓                                                   │
│  ┌─────────────────────────────────────────┐               │
│  │ Initial Prompt Generation               │               │
│  │ - System instructions                   │               │
│  │ - Available commands                    │               │
│  │ - Output format (JSON)                  │               │
│  └─────────────────────────────────────────┘               │
│         ↓                                                   │
│  ┌─────────────────────────────────────────┐               │
│  │ GPT-4 Returns JSON:                     │               │
│  │ {                                       │               │
│  │   "thoughts": {...},                    │               │
│  │   "command": {"name": "...", "args": {}}│               │
│  │ }                                       │               │
│  └─────────────────────────────────────────┘               │
│         ↓                                                   │
│  ┌─────────────────────────────────────────┐               │
│  │ Command Execution                       │               │
│  │ - google_search, browse_website         │               │
│  │ - write_to_file, read_file              │               │
│  │ - execute_python                        │               │
│  └─────────────────────────────────────────┘               │
│         ↓                                                   │
│  ┌─────────────────────────────────────────┐               │
│  │ Memory Update                           │               │
│  │ - Short-term: Recent context            │               │
│  │ - Long-term: Vector store (Top-K)       │               │
│  └─────────────────────────────────────────┘               │
│         ↓                                                   │
│  [Loop until task_complete command]                        │
│                                                             │
└────────────────────────────────────────────────────────────┘
```

**System Prompt Structure:**

```text
You are {ai_name}, {ai_role}
Your decisions must always be made independently.

GOALS:
1. {goal_1}
2. {goal_2}
...

COMMANDS:
1. google_search: Search Google, args: "query": "<query>"
2. browse_website: Browse Website, args: "url": "<url>", "question": "<question>"
3. write_to_file: Write to file, args: "file": "<file>", "text": "<text>"
...

RESPONSE FORMAT:
{
    "thoughts": {
        "text": "<thought>",
        "reasoning": "<reasoning>",
        "plan": "- short bulleted\n- list of steps",
        "criticism": "<constructive self-criticism>",
        "speak": "<summary to user>"
    },
    "command": {
        "name": "<command_name>",
        "args": {"arg_name": "value"}
    }
}
```

---

### Example 4: BabyAGI Task-Driven Agent

**Framework:** BabyAGI  
**Pattern:** Task creation, prioritization, and execution loop  
**Source:** [github.com/yoheinakajima/babyagi](https://github.com/yoheinakajima/babyagi)

```python
class BabyAGI:
    def __init__(self, objective: str):
        self.objective = objective
        self.task_list = deque()
        self.task_id_counter = 1

    def run(self):
        # Initial task
        self.add_task({"name": f"Develop a task list for: {self.objective}"})

        while self.task_list:
            # 1. Get highest priority task
            task = self.task_list.popleft()

            # 2. Execute task
            result = self.execution_agent(task)

            # 3. Store result in memory
            self.store_result(task, result)

            # 4. Create new tasks based on result
            new_tasks = self.task_creation_agent(
                objective=self.objective,
                completed_task=task,
                result=result
            )

            for new_task in new_tasks:
                self.add_task(new_task)

            # 5. Reprioritize task list
            self.task_list = self.prioritization_agent(self.task_list)
```

**Task Creation Prompt:**

```text
You are a task creation AI. Based on the result of the last completed task,
create new tasks that need to be completed to achieve the overall objective.

Objective: {objective}
Last completed task: {task}
Result: {result}
Existing incomplete tasks: {task_list}

Create new tasks (if needed) that do not overlap with existing tasks.
Return as a numbered list.
```

---

### Example 5: CrewAI Multi-Agent Team

**Framework:** CrewAI  
**Pattern:** Role-based multi-agent collaboration  
**Source:** [github.com/crewAIInc/crewAI](https://github.com/crewAIInc/crewAI)

```python
from crewai import Agent, Task, Crew, Process

# Define agents with roles
researcher = Agent(
    role="Senior Research Analyst",
    goal="Uncover cutting-edge developments in AI",
    backstory="""You are a senior research analyst at a leading tech think tank.
    Your expertise lies in identifying emerging trends and analyzing complex data.""",
    tools=[search_tool, scrape_tool],
    allow_delegation=False
)

writer = Agent(
    role="Tech Content Strategist",
    goal="Craft compelling content on tech advancements",
    backstory="""You are a renowned content strategist known for making complex
    tech concepts accessible and engaging.""",
    tools=[],
    allow_delegation=True
)

# Define tasks
research_task = Task(
    description="Conduct comprehensive research on the latest AI agent architectures",
    expected_output="A detailed report with at least 10 key findings",
    agent=researcher
)

writing_task = Task(
    description="Write a blog post about AI agents for a technical audience",
    expected_output="A 1500-word blog post with code examples",
    agent=writer,
    context=[research_task]  # Depends on research
)

# Create crew
crew = Crew(
    agents=[researcher, writer],
    tasks=[research_task, writing_task],
    process=Process.sequential,  # or Process.hierarchical
    verbose=True
)

result = crew.kickoff()
```

**Process Types:**

- **Sequential:** Tasks execute in order, output flows to next task
- **Hierarchical:** Manager agent delegates to worker agents

---

### Example 6: Microsoft AutoGen Conversational Agents

**Framework:** AutoGen  
**Pattern:** Multi-agent conversation orchestration  
**Source:** [github.com/microsoft/autogen](https://github.com/microsoft/autogen)

```python
from autogen_agentchat.agents import AssistantAgent
from autogen_agentchat.teams import RoundRobinGroupChat
from autogen_ext.models.openai import OpenAIChatCompletionClient

# Create model client
model_client = OpenAIChatCompletionClient(model="gpt-4")

# Define specialized agents
analyst = AssistantAgent(
    name="data_analyst",
    model_client=model_client,
    system_message="""You are a data analyst. Analyze data and provide insights.
    When you have completed analysis, say 'ANALYSIS COMPLETE'."""
)

programmer = AssistantAgent(
    name="programmer",
    model_client=model_client,
    system_message="""You are a Python programmer. Write code to implement solutions.
    Always test your code before submitting.""",
    tools=[code_execution_tool]
)

reviewer = AssistantAgent(
    name="code_reviewer",
    model_client=model_client,
    system_message="""You are a code reviewer. Review code for bugs and improvements.
    Say 'APPROVED' when code is ready."""
)

# Create team with round-robin speaking order
team = RoundRobinGroupChat(
    participants=[analyst, programmer, reviewer],
    max_messages=20
)

# Run conversation
result = await team.run(task="Analyze sales data and create a visualization")
```

**Orchestration Patterns:**

- **RoundRobinGroupChat:** Agents speak in fixed order
- **SelectorGroupChat:** Model selects next speaker dynamically
- **Swarm:** Manager hands off to any agent

---

### Example 7: Semantic Kernel Plugin-Based Agent

**Framework:** Semantic Kernel  
**Pattern:** Plugin/function-based agent  
**Source:** [github.com/microsoft/semantic-kernel](https://github.com/microsoft/semantic-kernel)

```python
import semantic_kernel as sk
from semantic_kernel.functions import kernel_function

class MathPlugin:
    @kernel_function(description="Add two numbers")
    def add(self, a: float, b: float) -> float:
        return a + b

    @kernel_function(description="Multiply two numbers")
    def multiply(self, a: float, b: float) -> float:
        return a * b

class SearchPlugin:
    @kernel_function(description="Search the web")
    def search(self, query: str) -> str:
        return web_search(query)

# Create kernel
kernel = sk.Kernel()
kernel.add_plugin(MathPlugin(), "math")
kernel.add_plugin(SearchPlugin(), "search")

# Create agent with automatic function calling
agent = kernel.create_agent(
    name="assistant",
    instructions="Help users with calculations and information lookup",
    plugins=["math", "search"]
)

response = await agent.invoke("What is 15% of Apple's current stock price?")
```

---

### Example 8: OpenAI Assistants API Agent

**Framework:** OpenAI Assistants API  
**Pattern:** Managed agent with built-in tools  
**Source:** [platform.openai.com](https://platform.openai.com/docs/assistants)

```python
from openai import OpenAI

client = OpenAI()

# Create assistant with tools
assistant = client.beta.assistants.create(
    name="Data Analyst",
    instructions="""You are a data analyst. Use code interpreter to analyze
    data and create visualizations. Use file search to find relevant documents.""",
    model="gpt-4-turbo",
    tools=[
        {"type": "code_interpreter"},
        {"type": "file_search"}
    ]
)

# Create thread
thread = client.beta.threads.create()

# Add message
message = client.beta.threads.messages.create(
    thread_id=thread.id,
    role="user",
    content="Analyze the attached CSV and create a summary chart",
    attachments=[{"file_id": file.id, "tools": [{"type": "code_interpreter"}]}]
)

# Run and poll
run = client.beta.threads.runs.create_and_poll(
    thread_id=thread.id,
    assistant_id=assistant.id
)

# Get response
messages = client.beta.threads.messages.list(thread_id=thread.id)
```

---

### Example 9: Claude Computer Use Agent

**Framework:** Anthropic Claude  
**Pattern:** GUI interaction agent  
**Source:** Anthropic Computer Use API

```python
import anthropic

client = anthropic.Anthropic()

# Agent that can control computer
response = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=4096,
    tools=[
        {
            "type": "computer_20241022",
            "name": "computer",
            "display_width_px": 1920,
            "display_height_px": 1080
        }
    ],
    messages=[
        {
            "role": "user",
            "content": "Open Chrome, go to weather.com, and tell me today's forecast"
        }
    ]
)

# Agent returns actions like:
# {"type": "computer_20241022", "action": "screenshot"}
# {"type": "computer_20241022", "action": "click", "coordinate": [500, 300]}
# {"type": "computer_20241022", "action": "type", "text": "weather.com"}
```

---

### Example 10: Voyager (Minecraft) Skill-Building Agent

**Framework:** Voyager  
**Pattern:** Curriculum learning with skill library  
**Source:** [voyager.minedojo.org](https://voyager.minedojo.org/)

```python
class Voyager:
    def __init__(self):
        self.skill_library = SkillLibrary()
        self.curriculum = AutoCurriculum()

    def run(self):
        while True:
            # 1. Curriculum proposes next task
            task = self.curriculum.propose_task(
                current_state=self.get_game_state(),
                completed_skills=self.skill_library.list_skills()
            )

            # 2. Retrieve relevant skills
            relevant_skills = self.skill_library.retrieve(task)

            # 3. Generate code to accomplish task
            code = self.code_generator.generate(
                task=task,
                skills=relevant_skills,
                game_state=self.get_game_state()
            )

            # 4. Execute in game
            success, feedback = self.execute(code)

            # 5. Self-verify and refine
            if not success:
                code = self.self_verification(code, feedback)
                success, _ = self.execute(code)

            # 6. Add to skill library if successful
            if success:
                self.skill_library.add(task, code)
```

**Key Innovation:** Builds a library of reusable skills over time, enabling increasingly complex tasks.

---

### Example 11: SWE-Agent (Software Engineering)

**Framework:** SWE-Agent  
**Pattern:** Code editing agent with test verification  
**Source:** [github.com/princeton-nlp/SWE-agent](https://github.com/princeton-nlp/SWE-agent)

```
┌────────────────────────────────────────────────────────────┐
│                    SWE-Agent Flow                           │
├────────────────────────────────────────────────────────────┤
│                                                             │
│  GitHub Issue/Bug Report                                    │
│         ↓                                                   │
│  ┌─────────────────────────────────────────┐               │
│  │ 1. Localize: Find relevant files        │               │
│  │    - grep, find, file_search            │               │
│  └─────────────────────────────────────────┘               │
│         ↓                                                   │
│  ┌─────────────────────────────────────────┐               │
│  │ 2. Understand: Read and analyze code    │               │
│  │    - read_file, scroll, search          │               │
│  └─────────────────────────────────────────┘               │
│         ↓                                                   │
│  ┌─────────────────────────────────────────┐               │
│  │ 3. Edit: Apply fix                      │               │
│  │    - edit_file, create_file             │               │
│  └─────────────────────────────────────────┘               │
│         ↓                                                   │
│  ┌─────────────────────────────────────────┐               │
│  │ 4. Verify: Run tests                    │               │
│  │    - pytest, run_tests                  │               │
│  └─────────────────────────────────────────┘               │
│         ↓                                                   │
│  Pass? → Submit patch                                       │
│  Fail? → Back to step 2                                    │
│                                                             │
└────────────────────────────────────────────────────────────┘
```

---

### Example 12: ChatDev Software Company Simulation

**Framework:** ChatDev  
**Pattern:** Multi-role software development simulation  
**Source:** [github.com/OpenBMB/ChatDev](https://github.com/OpenBMB/ChatDev)

```yaml
# ChatDev Agent Roles
agents:
  - CEO:
      role: "Make strategic decisions and review proposals"

  - CPO:
      role: "Design product requirements and UX"

  - CTO:
      role: "Make technology decisions and architecture"

  - Programmer:
      role: "Implement code based on designs"
      tools: [save_file, read_file, search_in_files]

  - CodeReviewer:
      role: "Review code quality and find bugs"

  - Tester:
      role: "Write and run tests"

# Workflow phases
phases:
  1. Demand Analysis: [CEO, CPO]
  2. Architecture Design: [CPO, CTO]
  3. Implementation: [Programmer]
  4. Code Review: [Programmer, CodeReviewer]
  5. Testing: [Tester, Programmer]
  6. Documentation: [Programmer]
```

---

### Example 13: Generative Agents (Stanford)

**Framework:** Research prototype  
**Pattern:** Believable agents with memory  
**Source:** [Park et al., 2023](https://arxiv.org/abs/2304.03442)

```python
class GenerativeAgent:
    def __init__(self):
        self.memory_stream = []  # All observations
        self.reflections = []    # Higher-level insights

    def observe(self, observation: str):
        """Add observation with metadata"""
        self.memory_stream.append({
            "content": observation,
            "timestamp": now(),
            "recency": 1.0,
            "importance": self.rate_importance(observation),
            "relevance": 0.0  # Computed at retrieval time
        })

    def retrieve(self, query: str, k: int = 10):
        """Retrieve memories by recency + importance + relevance"""
        for memory in self.memory_stream:
            memory["relevance"] = cosine_similarity(embed(query), embed(memory["content"]))
            memory["score"] = (
                memory["recency"] * 1.0 +
                memory["importance"] * 1.0 +
                memory["relevance"] * 1.0
            )
        return sorted(self.memory_stream, key=lambda m: m["score"])[:k]

    def reflect(self):
        """Generate higher-level insights from recent memories"""
        recent = self.memory_stream[-100:]
        questions = self.generate_reflection_questions(recent)

        for question in questions:
            relevant = self.retrieve(question)
            insight = self.llm.generate(
                f"Based on these memories: {relevant}\n"
                f"What insight can you derive about: {question}"
            )
            self.reflections.append(insight)
```

---

### Example 14: MemGPT (Long-Context Management)

**Framework:** MemGPT  
**Pattern:** Virtual memory for LLMs  
**Source:** [github.com/cpacker/MemGPT](https://github.com/cpacker/MemGPT)

```python
class MemGPT:
    """Treats context window like virtual memory with paging"""

    def __init__(self, context_limit: int = 8000):
        self.main_context = []      # Active context (limited)
        self.archival_storage = []  # Long-term storage (unlimited)
        self.recall_storage = []    # Recent conversation history

    def process_message(self, message: str):
        # Add to recall
        self.recall_storage.append(message)

        # Check if context is getting full
        if self.count_tokens(self.main_context) > self.context_limit * 0.8:
            # Page out old context to archival
            self.page_out()

        # Generate response with function calls for memory management
        response = self.llm.generate(
            context=self.main_context,
            tools=[
                "archival_memory_insert",  # Save to long-term
                "archival_memory_search",  # Retrieve from long-term
                "conversation_search",      # Search recent messages
                "core_memory_append",       # Update persona/user info
                "core_memory_replace"       # Modify core memories
            ]
        )

        return response
```

---

### Example 15: Toolformer (Self-Taught Tool Use)

**Framework:** Research model  
**Pattern:** Self-supervised tool learning  
**Source:** [Schick et al., 2023](https://arxiv.org/abs/2302.04761)

```
Training Process:
1. Sample text from dataset
2. Use LLM to insert potential API calls: "The population is [QA(population of Tokyo?)]"
3. Execute the API calls
4. Keep insertions that improve perplexity: "The population is [QA(population of Tokyo?)] → 14 million"
5. Fine-tune model on filtered examples

Inference:
- Model generates text with API call tokens: "The capital of France is [QA(capital of France?)]"
- System executes API: QA("capital of France?") → "Paris"
- Model continues: "The capital of France is Paris"
```

**Supported Tools:**

- Calculator: `[Calculator(15 * 0.12)]`
- Q&A: `[QA(who invented the telephone?)]`
- Wikipedia: `[WikiSearch(Albert Einstein)]`
- Machine Translation: `[MT(Hello → Spanish)]`

---

### Example 16: WebGPT (Grounded Web Research)

**Framework:** OpenAI Research  
**Pattern:** Browsing + citation agent  
**Source:** [OpenAI WebGPT Paper](https://arxiv.org/abs/2112.09332)

```
Commands:
- Search[query]: Submit search query
- Click[link_text]: Click on a link
- Quote[text]: Select text as evidence
- Scroll[direction]: Scroll up/down
- Back: Go back
- Answer[response]: Provide final answer with citations

Example Trajectory:
User: What year was the Eiffel Tower built?

Action: Search["Eiffel Tower construction year"]
Observation: [Search results showing Wikipedia, history sites...]

Action: Click["Eiffel Tower - Wikipedia"]
Observation: [Wikipedia page content...]

Action: Quote["Construction began in 1887 and was completed in 1889"]
Observation: [Quote saved]

Action: Answer["The Eiffel Tower was built between 1887 and 1889 [1]"]
```

---

### Example 17: Chain-of-Table Agent

**Framework:** Research  
**Pattern:** Iterative table manipulation  
**Source:** [Wang et al., 2024](https://arxiv.org/abs/2401.04398)

```python
class ChainOfTableAgent:
    """Answers questions by iteratively transforming tables"""

    operations = [
        "add_column",      # Add derived column
        "select_row",      # Filter rows
        "select_column",   # Select columns
        "group_by",        # Aggregate
        "sort_by",         # Sort table
    ]

    def answer(self, question: str, table: DataFrame):
        chain = []
        current_table = table

        while True:
            # LLM decides next operation
            op = self.llm.generate(
                f"Question: {question}\n"
                f"Current table: {current_table}\n"
                f"Previous operations: {chain}\n"
                f"What operation should be applied next?"
            )

            if op == "ANSWER":
                return self.generate_answer(question, current_table)

            # Apply operation
            current_table = self.apply_operation(op, current_table)
            chain.append(op)
```

---

### Example 18: Code Interpreter Agent

**Framework:** Various (OpenAI, Claude, etc.)  
**Pattern:** Write-execute-iterate code loop

```python
class CodeInterpreterAgent:
    def __init__(self):
        self.sandbox = SecureSandbox()
        self.session_vars = {}

    def process(self, user_request: str):
        messages = [{"role": "user", "content": user_request}]

        while True:
            # Generate code
            response = self.llm.generate(
                messages=messages,
                tools=[{
                    "type": "function",
                    "function": {
                        "name": "execute_python",
                        "description": "Execute Python code in sandbox",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "code": {"type": "string"}
                            }
                        }
                    }
                }]
            )

            if response.has_tool_call("execute_python"):
                code = response.tool_calls[0].arguments["code"]
                result = self.sandbox.execute(code)
                messages.append({"role": "tool", "content": result})
            else:
                return response.content
```

---

### Example 19: Multi-Modal Vision Agent

**Framework:** GPT-4V / Claude Vision  
**Pattern:** Image analysis with tool augmentation

```python
class VisionAgent:
    def analyze_and_act(self, image: bytes, task: str):
        # First pass: understand the image
        understanding = self.vision_llm.generate(
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "image", "image": image},
                        {"type": "text", "text": f"Analyze this image for: {task}"}
                    ]
                }
            ]
        )

        # Decide on actions based on understanding
        actions = self.llm.generate(
            f"Based on this analysis: {understanding}\n"
            f"What actions should be taken for: {task}?",
            tools=[
                "crop_image",
                "ocr_extract",
                "object_detection",
                "face_recognition",
                "save_annotation"
            ]
        )

        # Execute actions
        for action in actions:
            self.execute_tool(action)
```

---

### Example 20: RAG Agent with Adaptive Retrieval

**Framework:** LlamaIndex / LangChain  
**Pattern:** Retrieve-Augmented Generation with active retrieval

```python
class AdaptiveRAGAgent:
    def __init__(self):
        self.vector_store = VectorStore()
        self.graph_store = GraphStore()

    def answer(self, query: str):
        # 1. Analyze query type
        query_type = self.classify_query(query)

        # 2. Choose retrieval strategy
        if query_type == "factual":
            docs = self.vector_store.similarity_search(query, k=5)
        elif query_type == "relational":
            docs = self.graph_store.traverse(query)
        elif query_type == "temporal":
            docs = self.vector_store.search_with_date_filter(query)

        # 3. Generate with sources
        response = self.llm.generate(
            f"Answer based on these sources:\n{docs}\n\nQuery: {query}"
        )

        # 4. Check if more retrieval needed (active retrieval)
        if self.needs_more_info(response, query):
            follow_up = self.generate_follow_up_query(query, response)
            additional_docs = self.vector_store.search(follow_up)
            response = self.llm.generate(
                f"Previous answer: {response}\n"
                f"Additional context: {additional_docs}\n"
                f"Refined answer:"
            )

        return response
```

---

### Example 21: SQL Agent

**Framework:** LangChain / Custom  
**Pattern:** Natural language to SQL with verification

```python
class SQLAgent:
    def __init__(self, database):
        self.db = database
        self.schema = self.get_schema()

    def query(self, natural_language_query: str):
        # 1. Generate SQL
        sql = self.llm.generate(
            f"Database schema:\n{self.schema}\n\n"
            f"Convert to SQL: {natural_language_query}\n"
            f"Return only the SQL query."
        )

        # 2. Validate SQL (syntax check)
        if not self.is_valid_sql(sql):
            sql = self.fix_sql(sql)

        # 3. Execute with safety checks
        if self.is_safe_query(sql):  # No DROP, DELETE without WHERE, etc.
            result = self.db.execute(sql)
        else:
            return "Query blocked for safety reasons"

        # 4. Format response
        response = self.llm.generate(
            f"Query: {natural_language_query}\n"
            f"SQL: {sql}\n"
            f"Result: {result}\n"
            f"Provide a natural language summary."
        )

        return response
```

---

### Example 22: Customer Service Agent (Production Example)

**Framework:** OpenAI Agents SDK  
**Pattern:** Multi-tool customer service with escalation

```python
from agents import Agent, function_tool, Runner

@function_tool
def lookup_order(order_id: str) -> dict:
    """Look up order details by order ID"""
    return db.orders.find_one({"id": order_id})

@function_tool
def process_refund(order_id: str, reason: str) -> str:
    """Process a refund for an order"""
    return payment_service.refund(order_id, reason)

@function_tool
def escalate_to_human(summary: str, priority: str) -> str:
    """Escalate issue to human agent"""
    return ticket_system.create(summary, priority)

customer_service_agent = Agent(
    name="customer_service",
    instructions="""You are a helpful customer service agent for an e-commerce company.

CAPABILITIES:
- Look up order status and details
- Process refunds for eligible orders (within 30 days, unused items)
- Answer product questions
- Escalate complex issues to human agents

GUIDELINES:
1. Always verify the customer's order before taking action
2. Be empathetic but professional
3. Only process refunds that meet eligibility criteria
4. Escalate if the customer is frustrated or issue is complex
5. Never share other customers' information

REFUND POLICY:
- Full refund within 30 days for unused items
- Partial refund (50%) for opened items within 30 days
- No refunds after 30 days except for defects
""",
    tools=[lookup_order, process_refund, escalate_to_human]
)

# Run with guardrails
result = await Runner.run(
    customer_service_agent,
    "I want a refund for order #12345, the item arrived broken"
)
```

---

## Tool Integration Patterns

### Essential Tool Categories

| Category           | Purpose                  | Examples                           |
| ------------------ | ------------------------ | ---------------------------------- |
| **Retrieval**      | Get external information | Web search, RAG, database queries  |
| **Code Execution** | Verify and compute       | Python sandbox, shell, calculators |
| **Data Access**    | Structured data          | SQL, APIs, file systems            |
| **Communication**  | External actions         | Email, Slack, webhooks             |
| **Verification**   | Check correctness        | Unit tests, linters, validators    |

### Tool Definition Pattern (OpenAI-style)

```json
{
  "type": "function",
  "function": {
    "name": "search_database",
    "description": "Search the customer database for orders, returns, or account info",
    "parameters": {
      "type": "object",
      "properties": {
        "query_type": {
          "type": "string",
          "enum": ["orders", "returns", "account"],
          "description": "Type of data to search for"
        },
        "customer_id": {
          "type": "string",
          "description": "Customer ID to search"
        },
        "date_range": {
          "type": "object",
          "properties": {
            "start": { "type": "string", "format": "date" },
            "end": { "type": "string", "format": "date" }
          }
        }
      },
      "required": ["query_type", "customer_id"]
    }
  }
}
```

---

## Memory Architectures

### Three-Tier Memory System

```
┌─────────────────────────────────────────────────────────────┐
│                    AGENT MEMORY SYSTEM                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ SHORT-TERM MEMORY (Working Memory)                      │ │
│  │ - Current conversation context                          │ │
│  │ - Recent tool outputs                                   │ │
│  │ - Active plan/goals                                     │ │
│  │ Implementation: In-context, rolling buffer              │ │
│  └────────────────────────────────────────────────────────┘ │
│                           ↕                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ LONG-TERM MEMORY (Semantic)                             │ │
│  │ - Facts and knowledge                                   │ │
│  │ - User preferences                                      │ │
│  │ - Domain information                                    │ │
│  │ Implementation: Vector store + retrieval                │ │
│  └────────────────────────────────────────────────────────┘ │
│                           ↕                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ EPISODIC MEMORY (Experience)                            │ │
│  │ - Past task attempts                                    │ │
│  │ - What worked/failed                                    │ │
│  │ - Lessons learned                                       │ │
│  │ Implementation: Structured logs + reflection summaries  │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Context Window Management Strategy

```python
def build_context(state, budget=8000):
    """Pack context by priority within token budget"""
    context = []
    remaining = budget

    # 1. System instructions (required)
    context.append(system_prompt)
    remaining -= count_tokens(system_prompt)

    # 2. Current task/goal
    context.append(f"Current task: {state.task}")
    remaining -= count_tokens(state.task)

    # 3. Most recent observations (recency)
    recent = state.recent_messages[-5:]
    context.extend(recent)
    remaining -= count_tokens(recent)

    # 4. Retrieved relevant memories (relevance)
    relevant = memory.retrieve(state.task, k=10)
    for mem in relevant:
        if count_tokens(mem) < remaining:
            context.append(mem)
            remaining -= count_tokens(mem)

    # 5. Summarized older history (if space)
    if remaining > 500:
        summary = summarize(state.older_messages)
        context.append(summary)

    return context
```

---

## Orchestration Patterns

### 1. Manager Pattern (Hierarchical)

```
                    ┌─────────────┐
                    │   Manager   │
                    │   Agent     │
                    └─────────────┘
                    /      |      \
                   /       |       \
        ┌─────────┐  ┌─────────┐  ┌─────────┐
        │Research │  │ Writer  │  │ Editor  │
        │ Agent   │  │ Agent   │  │ Agent   │
        └─────────┘  └─────────┘  └─────────┘

Manager delegates tasks via tool calls
Maintains unified context and control
```

### 2. Decentralized Pattern (Peer-to-Peer)

```
        ┌─────────┐ ─── handoff ──→ ┌─────────┐
        │  Sales  │                  │ Support │
        │  Agent  │ ←── handoff ─── │  Agent  │
        └─────────┘                  └─────────┘
             ↑                            ↑
             │                            │
          handoff                      handoff
             │                            │
             ↓                            ↓
        ┌─────────┐                  ┌─────────┐
        │Technical│                  │ Billing │
        │  Agent  │                  │  Agent  │
        └─────────┘                  └─────────┘

Agents hand off control directly to peers
Each agent can interact with user
```

### 3. Blackboard Pattern (Shared State)

```
┌──────────────────────────────────────────────────────┐
│                    BLACKBOARD                         │
│  ┌──────────────────────────────────────────────┐   │
│  │ Shared State:                                 │   │
│  │ - Current hypothesis                          │   │
│  │ - Evidence gathered                           │   │
│  │ - Open questions                              │   │
│  │ - Task assignments                            │   │
│  └──────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
         ↑        ↑        ↑        ↑
         │        │        │        │
    ┌────┴──┐ ┌───┴───┐ ┌──┴──┐ ┌──┴───┐
    │Agent 1│ │Agent 2│ │Agent│ │Agent │
    │       │ │       │ │  3  │ │  4   │
    └───────┘ └───────┘ └─────┘ └──────┘

Agents read/write to shared blackboard
Coordination through shared state
```

---

## Prompt Engineering for Agents

### System Prompt Template

```text
# IDENTITY
You are {agent_name}, {role_description}.

# CAPABILITIES
You have access to the following tools:
{tool_descriptions}

# INSTRUCTIONS
{step_by_step_instructions}

# CONSTRAINTS
- {constraint_1}
- {constraint_2}
- {constraint_3}

# OUTPUT FORMAT
{expected_output_format}

# EXAMPLES
{few_shot_examples}
```

### Tool Selection Prompt

```text
Given the user's request and available tools, decide which tool to use.

User Request: {request}

Available Tools:
{tools_with_descriptions}

Think step by step:
1. What is the user trying to accomplish?
2. What information or action is needed?
3. Which tool best matches this need?

Selected Tool: {tool_name}
Arguments: {arguments}
Reasoning: {why_this_tool}
```

### Verification/Critic Prompt

```text
You are a quality assurance reviewer. Evaluate the following response.

Original Request: {request}
Agent Response: {response}
Sources Used: {sources}

Evaluate on these criteria:
1. Correctness: Is the information accurate?
2. Completeness: Does it fully address the request?
3. Safety: Are there any concerning elements?
4. Citations: Are sources properly referenced?

Issues Found:
{list_of_issues}

Verdict: {PASS/FAIL}
Required Fixes: {fixes_if_any}
```

---

## Framework Comparison

| Framework             | Best For          | Pattern          | Multi-Agent     | Memory        | Language       |
| --------------------- | ----------------- | ---------------- | --------------- | ------------- | -------------- |
| **LangChain**         | General agents    | ReAct, Tool-use  | Via LangGraph   | Built-in      | Python/JS      |
| **LangGraph**         | Complex workflows | State machine    | Native          | Checkpointing | Python/JS      |
| **AutoGen**           | Research/Chat     | Conversational   | Native          | Agent-based   | Python/.NET    |
| **CrewAI**            | Team simulation   | Role-based       | Native          | Multi-tier    | Python         |
| **Semantic Kernel**   | Enterprise        | Plugin-based     | Planners        | Session       | Python/C#/Java |
| **OpenAI Agents SDK** | Production        | Function-calling | Manager/Handoff | Sessions      | Python         |
| **LlamaIndex**        | RAG-focused       | Query engines    | Agents          | Native        | Python         |

---

## References

### Papers

1. [ReAct: Synergizing Reasoning and Acting](https://arxiv.org/abs/2210.03629) - Yao et al., 2022
2. [Toolformer: Language Models Can Teach Themselves to Use Tools](https://arxiv.org/abs/2302.04761) - Schick et al., 2023
3. [Reflexion: Language Agents with Verbal Reinforcement Learning](https://arxiv.org/abs/2303.11366) - Shinn et al., 2023
4. [Generative Agents: Interactive Simulacra of Human Behavior](https://arxiv.org/abs/2304.03442) - Park et al., 2023
5. [Tree of Thoughts: Deliberate Problem Solving with LLMs](https://arxiv.org/abs/2305.10601) - Yao et al., 2023
6. [Voyager: An Open-Ended Embodied Agent](https://arxiv.org/abs/2305.16291) - Wang et al., 2023
7. [WebGPT: Browser-assisted Question-answering](https://arxiv.org/abs/2112.09332) - Nakano et al., 2022

### Open Source Repositories

- [LangChain](https://github.com/langchain-ai/langchain)
- [LangGraph](https://github.com/langchain-ai/langgraph)
- [AutoGPT](https://github.com/Significant-Gravitas/Auto-GPT)
- [BabyAGI](https://github.com/yoheinakajima/babyagi)
- [Microsoft AutoGen](https://github.com/microsoft/autogen)
- [CrewAI](https://github.com/crewAIInc/crewAI)
- [LlamaIndex](https://github.com/run-llama/llama_index)
- [ChatDev](https://github.com/OpenBMB/ChatDev)
- [SWE-Agent](https://github.com/princeton-nlp/SWE-agent)
- [MemGPT](https://github.com/cpacker/MemGPT)
- [Guidance](https://github.com/guidance-ai/guidance)

### Documentation & Guides

- [OpenAI: A Practical Guide to Building Agents](https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf)
- [Anthropic: Building Effective Agents](https://docs.anthropic.com/)
- [Microsoft AI Agents for Beginners](https://microsoft.github.io/ai-agents-for-beginners/)
- [LangChain Agent Documentation](https://python.langchain.com/docs/modules/agents/)

---

## Quick Reference: Choosing an Agent Pattern

```
START
  │
  ▼
Is task simple with clear steps?
  │
  ├── YES → Single Agent with Tools
  │
  └── NO → Does it require planning?
              │
              ├── YES → Plan-and-Execute
              │
              └── NO → Is it exploratory?
                          │
                          ├── YES → ReAct Loop
                          │
                          └── NO → Does it need self-correction?
                                      │
                                      ├── YES → Reflexion
                                      │
                                      └── NO → Multiple specialists needed?
                                                  │
                                                  ├── YES → Multi-Agent (CrewAI/AutoGen)
                                                  │
                                                  └── NO → Single ReAct Agent
```

---

_Report generated: January 2026_  
_Based on research from academic papers, open-source frameworks, and production implementations._
