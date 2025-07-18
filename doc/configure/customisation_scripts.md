<div class="hidden-warning"><a href="https://docs.haskellstack.org/"><img src="https://cdn.jsdelivr.net/gh/commercialhaskell/stack/doc/img/hidden-warning.svg"></a></div>

# Customisation scripts

## GHC installation customisation

[:octicons-tag-24: 2.9.1](https://github.com/commercialhaskell/stack/releases/tag/v2.9.1)

On Unix-like operating systems and Windows, Stack's installation procedure can
be fully customised by placing a `sh` shell script (a 'hook') in the
[Stack root](../topics/stack_root.md) directory at `hooks/ghc-install.sh`. On
Unix-like operating systems, the script file must be made executable. The script
is run by the `sh` application (which is provided by MSYS2 on Windows).

The script **must** return an exit code of `0` and the standard output **must**
be the absolute path to the GHC binary that was installed. Otherwise Stack will
ignore the script and possibly fall back to its own installation procedure.

When `system-ghc: true`, the script is not run. That is because the two
mechanisms reflect distinct concepts, namely:

* `system-ghc: true` causes Stack to search the PATH for a version of GHC; and

* `hooks/ghc-install.sh` causes Stack to execute a script that is intended to
  send to standard output a path to a version of GHC. The path in question may
  or may not be in the PATH. The script may also do other things, including
  installation.

When `install-ghc: false`, the script is still run. That allows you to ensure
that only your script will install GHC and Stack will not default to its own
installation logic, even when the script fails.

The following environment variables are always available to the script:

* `HOOK_GHC_TYPE = "bindist" | "git" | "ghcjs"`

For "bindist", additional variables are:

* `HOOK_GHC_VERSION = <ver>`

For "git", additional variables are:

* `HOOK_GHC_COMMIT = <commit>`
* `HOOK_GHC_FLAVOR = <flavor>`

For "ghcjs", additional variables are:

* `HOOK_GHC_VERSION = <ver>`
* `HOOK_GHCJS_VERSION = <ver>`

An example script is:

~~~sh
#!/bin/sh

set -eu

case $HOOK_GHC_TYPE in
	bindist)
		# install GHC here, not printing to stdout, e.g.:
		#   command install $HOOK_GHC_VERSION >/dev/null
		;;
	git)
		>&2 echo "Hook does not support installing from source"
		exit 1
		;;
	*)
		>&2 echo "Unsupported GHC installation type: $HOOK_GHC_TYPE"
		exit 2
		;;
esac

echo "location/to/ghc/executable"
~~~

If the following script is installed by GHCup, GHCup makes use of it, so that if
Stack needs a version of GHC, GHCup takes over obtaining and installing that
version:

~~~sh
#!/bin/sh

set -eu

case $HOOK_GHC_TYPE in
    bindist)
        ghcdir=$(ghcup whereis --directory ghc "$HOOK_GHC_VERSION" || ghcup run --ghc "$HOOK_GHC_VERSION" --install) || exit 3
        printf "%s/ghc" "${ghcdir}"
        ;;
    git)
        # TODO: should be somewhat possible
        >&2 echo "Hook does not support installing from source"
        exit 1
        ;;
    *)
        >&2 echo "Unsupported GHC installation type: $HOOK_GHC_TYPE"
        exit 2
        ;;
esac
~~~

## `--file-watch` post-processing

[:octicons-tag-24: 3.1.1](https://github.com/commercialhaskell/stack/releases/tag/v3.1.1)

On Unix-like operating systems and Windows, Stack's `build --file-watch`
post-processing can be fully customised by specifying an executable or a `sh`
shell script (a 'hook') using the
[`file-watch-hook`](yaml/non-project.md#file-watch-hook)
non-project specific configuration option. On Unix-like operating systems, the
script file must be made executable. A script is run by the `sh` application
(which is provided by MSYS2 on Windows).

The following environment variables are always available to the executable or
script:

* `HOOK_FW_RESULT` (Equal to `""` if the build did not fail. Equal to the result
  of `displayException e`, if exception `e` thown during the build.)

An example script is:

~~~sh
#!/bin/sh

set -eu

if [ -z "$HOOK_FW_RESULT" ]; then
  echo "Success! Waiting for next file change."
else
  echo "Build failed with exception:"
  echo $HOOK_FW_RESULT
fi
~~~
