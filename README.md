# Apex Log Analyzer

This is a plugin that replicates VSCode's apex log analyzer. It is highly personalised to my needs, but it still has a lot of nice featues when workin with Salesforce logs. 

I suggest you fork this repo and modify it as you wish. It works best when it is highly customized to personal needs. 

It was built using various AI tools as an exercise to see if AI agenets and tools can build personalized apps/extensions. 

## Installation

- Use your favorite plugin manager to install! 
- lazy example:

```lua
    {
      'Kristijan-K/log-analyzer',
      config = function()
        vim.keymap.set('n', '<leader>xl', '<cmd>SFLogs<CR>', { desc = 'Analyze SF Logs' })
        vim.keymap.set('n', '<leader>xd', '<cmd>SFDiff<CR>', { desc = 'Diff SF Logs' })
      end,
    },


``` 

## Usage
Log analyzer can be invoked by using a command :SFLogs. It should be run on a buffer that contains Salesforce Apex Log file. 

The log analyzer is organized into several tabs, each providing a different view of the log data:

-   **User Debug:** Displays all `USER_DEBUG` log lines. This is useful for seeing specific debug output that you\'ve added to your code.
-   **Method Tree:** A collapsible tree view of the execution path. It shows the sequence of method calls, including their duration. You can expand and collapse nodes to analyze the call stack. This tab also includes the "10 Longest Operations" for quick performance analysis.
-   **SOQL:** Shows all SOQL queries, aggregated by the query string. You can sort them by the number of executions (`execs`), the number of rows returned (`rows`), or the execution time (`ms`). This is helpful for identifying inefficient queries.
-   **DML:** Lists all DML operations, sorted by the number of rows affected. This helps you find DML statements that are processing large numbers of records.
-   **Exceptions:** Displays any exceptions that occurred during the execution. This is crucial for debugging errors.
-   **Node Counts:** Shows a count of how many times each method or code unit appears in the execution tree, which can help identify frequently executed code paths.

SF Diff viewer can be invoked by uisng a command :SFDiff. It should be run on two buffers that contain Salesforce Apex Log file. One buffer should be the base log (current buffer), and the other should be the target log (selected via Telescope).

## Keybindings

### Global

-   `<Tab>`: Switch to the next tab.
-   `<S-Tab>`: Switch to the previous tab.
-   `q`: Close the log analyzer window.

### Method Tree Tab

-   `z`: Toggle (expand/collapse) the selected node in the tree.
-   `Z`: Toggle (expand/collapse) all nodes in the tree.
-   `t`: Toggle truncation of SOQL queries within the tree.
-   `T`: Toggle truncation of the `WHERE` clause in SOQL queries within the tree.
-   `s`: Toggle the display of empty nodes (nodes without SOQL or DML).

### SOQL Tab

-   `r`: Cycle through the sort modes (executions, rows, time).
-   `t`: Toggle truncation of SOQL queries.

### Node Counts Tab

-   `t`: Toggle truncation of SOQL queries.
-   `T`: Toggle truncation of the `WHERE` clause in SOQL queries.

### Exceptions Tab

-   `s`: Toggle the display of last SOQL query.

### Diff viewer

-   `q`: Close the diff viewer.

## Issues

Please file an issue. 

## Contribute

-   Fork
-   Create a feature branch
-   Make changes
-   Make PR

