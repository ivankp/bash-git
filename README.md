# Introduction

BashGit: Git helpers and Bash shell integration implemented in pure Bash.

On some systems, spawning a process may take a lot of time and create a noticible overhead for shell
scripting.
For example, the overhead may be caused by an antivirus or telemetry inspecting every process.
Even if that is not the case, the `git-prompt.sh` that comes with Git uses many `git` commands to
obtain the information to populate the `PS1` variable.
A lot of information useful for developers can be obtained from the names or contentes of the files
in the `.git` directory.
Processing this information in shell itself avoids the overhead of spawning additional processes and
can be noticibly faster.

In addition to the shell prompt integration, BashGit provides a number of helpful commands (also
implemented in Bash) for tasks that are difficult or slow to perform with `git` commands.

# Getting started

`git clone https://github.com/ivankp/bash-git.git`

In your `.bashrc`:
```bash
source /foo/bar/bash-git/bash-git.sh
PS0="$BASHGIT_PS0" # optional, prints current time at the start of command
PROMPT_COMMAND=BASHGIT_PROMPT_COMMAND # optional, modifies shell prompt
BASHGIT_REMOTES['git-server.com']='bitbucket' # optional, for `remote` command
```

# Shell prompt

The custom prompt is optional.
It is fast (~2 ms, much faster than `git-prompt.sh`) and easy to use.
I encourage users to give it a try.
But, you don't have to use it to be able to use any of the commands that BashGit provides.
In fact, just sourcing `bash-git.sh` won't modify your prompt.
You have to opt into the feature by adding the following lines in your `.bashrc`:
```bash
source /foo/bar/bash-git/bash-git.sh
PROMPT_COMMAND=BASHGIT_PROMPT_COMMAND # optional, modifies shell prompt
PS0="$BASHGIT_PS0" # optional, prints current time at the start of command
```

If you don't like the look of the BashGit prompt, take a look at the `BASHGIT_PROMPT_COMMAND`
function.
It defines a command that runs for every prompt to dynamically populate the `PS1` variable
and consists of a few bulding blocks, which you can easily adopt to construct your own
prompt command.
If you do this, I encourage you to define your own function instead of modifying
`BASHGIT_PROMPT_COMMAND` definition directly in `git-prompt.sh`,
so that you don't get comflicts when you pull from the bash-git repo.
BashGit is in active development.

Some of the BashGit prompt features include:
  - Colorized prompt
  - Command start time
  - Command execution timing
  - Number of background jobs indicator: `[1]`
  - Nested shell depth indicator: `$$`
  - Active python virtual environment indicator: 🐍
  - For Git repos:
    - current commit hash
    - current branch name
    - name of the origin remote

# Commands

List of commands:
- [`sm`](#sm)
- [`repo`](#repo)
- [`super`](#super)
- [`gl`](#gl)
- [`remote`](#remote)
- [`topic`](#topic)
- [`amend`](#amend)

## `sm`
Navigate and operate on the submodule tree.

### `sm -h`
Help

### `sm` (default behavior):
Lists all submodules recursively.

If you have [`fzf`](https://github.com/junegunn/fzf) installed,
running `sm` will display a list of submodule paths to select from.
Select one to `cd` into it.

`-o` option adds the names of the "origin" remotes of the submodules to the list.

`-p` forces the list to be printed instead of piped through `fzf`.
This is the default behavior if `fzf` command is not found.

`-x` start at the current repo level.
By default, `sm` looks for submodules starting at the root super-repo level.

### `sm -u`
Update submodules.
Runs `git submodule update --init` for the specified submodule paths
or adds `--recursive` if no paths are specified.

### `sm -b`
Without arguments, lists distinct name suffixes (parts after the last `/`) of all local branches in
all submodules.
Provide one or more of the branch name suffixes as arguments to list matching full branch names
and submodules containing them.

## `repo`
`cd` into the root directory of the current repo.

## `super`
`cd` into the root directory of the top level super-repo.

## `gl`
Terser git log

## `remote`
Prints a url to the web interface for the "origin" remote.
Two optional arguments, path and git reference, can be provided.
The default reference is `HEAD`.
The default path is the current directory.

The arguments can be provided in either order and either can be omitted.
The first argument to be successfully identified as an existing path is treated as the path and
the remaining one as the reference.

## `topic`
Create a `topic/TARGET/LABEL` branch, with target derived either from the current branch name or
from the branch name specified for the submodule in the super-repo's `.gitmodules` file.

If run without arguments, prints the `git` command that would be used to create a new topic branch.
This can be used to check the branch name before creating one.

If run with an argument, the argument is the value of the `LABEL` part of the branch name, and a
`topic/TARGET/LABEL` branch is created by running
```sh
git switch -c topic/TARGET/LABEL
```

## `amend`
Simplifies amending commits.

By default runs `git commit --amend --no-edit`. The following options modify the command:

- `-a`: add `--all`
- `-e`: remove `--no-edit`
- `-d`: add `--date=now`
- `-p`: also run `git push --force-with-lease` after amending the commit.
- `-h`: print help message and exit
