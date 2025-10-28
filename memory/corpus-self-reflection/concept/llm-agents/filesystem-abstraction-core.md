The filesystem abstraction pattern exposes heterogeneous data sources to LLM agents through a unified, familiar interface. Instead of creating specialized tools for each data source (databases, APIs, message queues), all data is presented as a virtual filesystem navigable using standard operations: `ls`, `cat`, `find`, `grep`, `cd`.

## Why This Works

**Existing Knowledge**: LLM agents are extensively trained on filesystem concepts. These operations are deeply embedded in their reasoning capabilities.

**Cognitive Efficiency**: Agents don't need to learn "how to query a database" vs "how to call an API" vs "how to read a file." It's all the same: navigate and read.

**Tool Composability**: Filesystem operations naturally compose. List files, filter by name, read entries, combine results—all using familiar patterns.

**Discoverability**: Agents can explore unknown data structures using `ls` and `find`. The filesystem structure itself documents available data.

## Core Principle

By mapping ANY data source to a filesystem-like structure, agents leverage existing knowledge to access data from any origin using the same tools and reasoning patterns. This eliminates teaching agents new tool patterns for each data source.

## Implementation Patterns

- **Databases as Directories**: Tables → directories, rows → files, columns → content
- **APIs as File Paths**: Endpoints → file hierarchies (e.g., `/api/github/repos/owner/repo/issues/123`)
- **Structured Data as Files**: JSON, YAML, CSV exposed as readable files
- **Real-time Data as Virtual Files**: Files computing content on read (e.g., `/system/metrics/cpu_usage`)
- **Search Results as Listings**: Query results appear as directory listings
- **Hierarchical Organization**: Directory depth represents data relationships