#!/bin/bash

# config
#-------------------------------------------------------------------------------

if [[ -z $XDG_CONFIG_HOME ]]; then
	# for mac os
	XDG_CONFIG_HOME="$HOME/.config"
fi

g_rctl="$(basename "$0")"
g_main_rctl="$XDG_CONFIG_HOME/rctl"
g_main_config="$g_main_rctl/rctl.env" # global config
g_main_commands_dir="$g_main_rctl/commands" # global custom commands
g_main_hooks_dir="$g_main_rctl/hooks" # global hooks

g_project_rctl=".local/rctl"
g_project_rctl=".rctl"
g_project_rctl_gitignore="/.local/"
g_project_rctl_gitignore="/.rctl/"
g_project_rctl_gitignore_grep="^/\.local(\$|/)"
g_project_rctl_gitignore_grep="^/\.rctl(\$|/)"
g_project_config="$g_project_rctl/project.env"
g_project_commands_dir="$g_project_rctl/commands"
g_project_hooks_dir="$g_project_rctl/hooks"
g_project_root_hints=($g_project_config)
g_initializable_root_hints=(".git")

g_rsync_opts="--recursive --executability --copy-links --delete -zz"


# library
#-------------------------------------------------------------------------------

OK=0
ERR=1

err_not_project="not in an project (use \`$g_rctl init\` to initialize)"
err_not_initializable="not in an initializable project (requires ${g_initializable_root_hints[@]})"

throw() {
	local mesg="$1"
	echo "error: $mesg" >&2
	exit $ERR
}

info() {
	local mesg="$1"
	echo -e "\e[94m* ${mesg}\e[0m"
}

detect_root() {
	local hints=("$@")
	local path="$PWD"

	for hint in "${hints[@]}"; do
		if [[ -e "$path/$hint" ]]; then
			return $OK
		fi
	done

	return $ERR
}

find_root() {
	local hints=("$@")
	local path="$PWD"
	local parent=""

	(
		cd "$path"

		while true; do
			if detect_root "${hints[@]}"; then
				echo "$PWD"
				return $OK
			fi

			if [[ $PWD == $parent ]]; then
				return $ERR
			fi

			parent="$PWD"
			cd ..
		done
	)
}

find_project_root() {
	find_root "${g_project_root_hints[@]}"
}

find_initializable_root() {
	find_root "${g_initializable_root_hints[@]}"
}

in_project() {
	find_project_root >/dev/null
}

in_initializable_project() {
	find_initializable_root >/dev/null
}

list_commands() {
	local basedir="$1"

	ls -1 $basedir | sed 's/\.bash//'
}

run_global_hook_if_exists() {
	local when="$1"
	local command="$2"

	if [[ $when != "before" && $when != "after" ]]; then
		throw "[fatal] hook moments must be before or after"
	fi

	if [[ -z $command ]]; then
		throw "[fatal] command parameter is required"
	fi

	hook="$g_main_hooks_dir/${when}_${command}.bash"

	if [[ -f $hook ]]; then
		#info "running global hook: $when $command"
		source "$hook"
	fi
}

run_project_hook_if_exists() {
	local when="$1"
	local command="$2"

	if [[ $when != "before" && $when != "after" ]]; then
		throw "[fatal] hook moments must be before or after"
	fi

	if [[ -z $command ]]; then
		throw "[fatal] command parameter is required"
	fi

	local project="$(find_project_root)"

	if [[ -n $project ]]; then
		hook="$project/$g_project_hooks_dir/${when}_${command}.bash"

		if [[ -f $hook ]]; then
			#info "running project hook: $when $command"
			source "$hook"
		fi
	fi
}

edit() {
	local file="$1"

	(
		source "$g_main_config"
		"$editor" "$file"
	)
}

project_list_targets() {
	if ! in_project; then
		throw "$err_not_project"
	fi

	(
		source "$(find_project_root)/$g_project_config"

		for target in "${targets[@]}"; do
			echo "$target"
		done
	)
}

project_has_target() {
	local target="$1"
	local project_target

	for project_target in "$(project_list_targets)"; do
		if [[ $project_target == $target ]]; then
			return $OK
		fi
	done

	return $ERR
}

usage() {
	local project="$(find_project_root)"
	local project_commands=""
	local main_commands="$(list_commands "$g_main_commands_dir")"

	if in_project; then
		project_commands="$(list_commands "$project/$g_project_commands_dir")"
	fi

	echo "rctl: remote control for your projects"
	echo
	echo "usage: rctl <command> [<args...>]"
	echo
	echo "build-in commands:"
	if ! in_project && in_initializable_project; then
		echo "    init"
		echo "        initialize rctl in a git project (in the current working directory)"
	fi
	if in_project; then
		echo "    ssh <target>"
		echo "        ssh to target remote"
		echo "    push <target>"
		echo "        deploy current project to the target remote"
		echo "    config"
		echo "        edit project configuration"
		echo "    edit-command <command>"
		echo "        edit a custom project command"
		echo "    edit-hook {before|after} <command>"
		echo "        edit (or create) a hook {pre|post}-<command>"
	fi
	echo "    help [<custom_command>]"
	echo "        print this help (or help about the specified custom command)"

	if [[ -n $project_commands ]]; then
		echo
		echo "project-specific commands:"
		for cmd in "$project_commands"; do
			echo "    $cmd [<args...>]"
			echo "        see \`$g_rctl help $cmd\` for details"
		done
	fi

	if [[ -n $main_commands ]]; then
		echo
		echo "global custom commands:"
		for cmd in "$main_commands"; do
			echo "    $cmd [<args...>]"
			echo "        see \`$g_rctl help $cmd\` for details"
		done
	fi

	echo
	echo "edit your global config in: $g_main_rctl"
}

rctl_setup() {
	if [[ ! -d $g_main_rctl ]]; then
		mkdir -p "$g_main_rctl"
		touch "$g_main_config"
		mkdir "$g_main_commands_dir"
		mkdir "$g_main_hooks_dir"

		(
			echo "editor=\"$EDITOR\""
			echo
			echo "# note: keep the quotes"
			echo "default_sync_include=\"(*)\""
			echo "default_sync_exclude=\"()\""
			echo "default_target=\"live\""
			echo "default_remote_host=\"\""
			echo "default_remote_user=\"\""
			echo "default_remote_dir=\"\""
		) >> "$g_main_config"
	fi

	if [[ ! -f $g_main_config ]]; then
		throw "invalid configuration directory: $g_main_rctl"
	fi
}


# commands
#-------------------------------------------------------------------------------

help() {
	local cmd="$1"

	if [[ -z $cmd ]]; then
		usage
		return $OK
	fi
}

project_init() {
	local project

	if ! in_initializable_project; then
		throw "$err_not_initializable"
	fi

	if in_project; then
		throw "this project has already been initialized"
	fi

	project="$(find_initializable_root)"

	local project_rctl="$project/$g_project_rctl"
	local project_gitignore="$project/.gitignore"

	local project_config="$project/$g_project_config"
	local project_commands_dir="$project/$g_project_commands_dir"
	local project_hooks_dir="$project/$g_project_hooks_dir"

	[[ -d $project_rctl ]] || mkdir -p "$project_rctl"

	if [[ ! -f $project_gitignore ]] || ! grep -E "$project_rctl_gitignore_grep" "$project_gitignore" >/dev/null; then
		echo "$project_rctl_gitignore" >> "$project_gitignore"
	fi

	[[ -d $project_commands_dir ]] || mkdir "$project_commands_dir"
	[[ -d $project_hooks_dir ]] || mkdir "$project_hooks_dir"

	if [[ ! -f $project_config ]]; then
		touch "$project_config"

		(
			source "$g_main_config"

			(
				echo "# rctl project configuration"
				echo "#"
				echo "# sync_dir: base directory to deploy (% is the project root)"
				echo "# sync_include: files to include (space-separated)"
				echo "# sync_exclude: files to exclude (space-separated)"
				echo "# targets: list of remote targets"
				echo "# remote_<target>: remote connection config (\"<host>\" \"<user>\" \"<remote_dir>\")"
				echo "#"
				echo "# notes about files to include:"
				echo "#     - \`(dist)\` will send the \`dist\` directory along with its contents"
				echo "#     - \`(dist/*)\` will send the contents of the \`dist\` directory (without the directory itself)"
				echo "#"
				echo "# notes about files to exclude:"
				echo "#     - you target remote files/directories for exclusion, not local (see inclusion rules)"
				echo "#     - for example, \`(dist/*.cache)\` will only work if you included the dist directory itself"
				echo
				echo "sync_include=$default_sync_include"
				echo "sync_exclude=$default_sync_exclude"
				echo
				echo "targets=($default_target)"
				echo "remote_$default_target=($default_remote_host $default_remote_user $default_remote_dir)"
			) >> "$project_config"
		)
	fi

	project_edit_config
}

project_edit_config() {
	if ! in_project; then
		throw "$err_not_project"
	fi

	edit "$(find_project_root)/$g_project_config"
}

project_edit_command() {
	local command="$1"
	local command_file

	local project="$(find_project_root)"

	if ! in_project; then
		throw "$err_not_project"
	fi

	if [[ -z $command ]]; then
		throw "requires the command name"
	fi

	if [[ ! $command =~ ^[a-z_][a-z0-9_-]*$ ]]; then
		throw "invalid command name"
	fi

	if ! in_project; then
		throw "$err_not_project"
	fi

	command_file="$project/$g_project_commands_dir/$command.bash"

	if [[ ! -f $command_file ]]; then
		touch "$command_file"

		(
			echo "# you can call all internal functions"
			echo
			echo "command_run() {"
			echo "}"
			echo
			echo "command_usage() {"
			echo "}"
			echo
			echo "command_autocomplete() {"
			echo "}"
		) >> $command_file
	fi

	edit "$command_file"
}

project_edit_hook() {
	local when="$1"
	local command="$2"

	local project="$(find_project_root)"
	local hook_file
	local command_file

	if ! in_project; then
		throw "$err_not_project"
	fi

	if [[ $when != "before" && $when != "after" ]]; then
		throw "hook moment should be 'before' or 'after'"
	fi

	if [[ -z $command ]]; then
		throw "requires the command name"
	fi

	if [[ ! $command =~ ^[a-z_][a-z0-9_-]*$ ]]; then
		throw "invalid command name"
	fi

	command_file="$project/$g_project_commands_dir/$command.bash"
	if [[ $command != "push" && $command != "ssh" && ! -f $command_file ]]; then
		throw "not a valid command"
	fi

	hook_file="$project/$g_project_hooks_dir/${when}_${command}.bash"

	if [[ ! -f $hook_file ]]; then
		touch "$hook_file"

		(
			echo "# project hook: $when $command"
			echo "#"
			echo "# you can call all rctl functions (see rctl.bash source), such as:"
			echo "#     * \`project_ssh <target> [<command> [<args...>]]\`"
			echo "#     * \`project_run <custom_command>\`"
			echo "#"
			echo "# you can access and modify all variables, such as:"
			echo "#     * \`project=\"\$project\"\` # current project root path"
			if [[ $command == "push" ]]; then
				echo "#     * \`sync_include=(\"\${sync_include[@]}\")\` # files to include"
				echo "#     * \`sync_exclude=(\"\${sync_exclude[@]}\")\` # files to exclude"
				echo "#     * \`rsync_opts=\"\$rsync_opts\"\` # rsync options (for example, to remote -zz for older servers)"
			fi
			if [[ $command == "ssh" ]]; then
				echo "#     * \`ssh_opts=(\"\${ssh_opts[@]}\")\` # options for ssh (default change dir, except if args not empty)"
			fi
			if [[ $command == "push" || $command == "ssh" ]]; then
				echo "#     * \`target=\"\$target\"\` # remote target"
				echo "#     * \`remote_host=\"\$remote_host\"\` # remote hostname"
				echo "#     * \`remote_user=\"\$remote_user\"\` # remote username"
				echo "#     * \`remote_dir=\"\$remote_dir\"\` # remote directory"
				echo "#     * \`args=(\"\${args[@]}\")\` # provided command line arguments"
			fi
			echo
			echo
		) >> $hook_file
	fi

	edit "$hook_file"
}

project_push() {
	local target="$1"; shift

	if [[ -z $target ]]; then
		throw "invalid usage"
	fi

	if ! in_project; then
		throw "$err_not_project"
	fi

	if ! project_has_target "$target"; then
		throw "target remote not defined (see \`$g_rctl config\`)"
	fi

	(
		local args=("$@")
		local project="$(find_project_root)"
		cd "$project" # required for rsync

		source "$(find_project_root)/$g_project_config"

		local remote="remote_$target"
		local remote_host="$(eval echo \"\${$remote[0]}\")"
		local remote_user="$(eval echo \"\${$remote[1]}\")"
		local remote_dir="$(eval echo \"\${$remote[2]}\")"

		local rsync=rsync
		local rsync_opts="$g_rsync_opts"

		run_global_hook_if_exists before push
		run_project_hook_if_exists before push

		local rsync_include=("${sync_include[@]}") # quote-enclosed, until the end
		local rsync_exclude=()

		for f in "${sync_exclude[@]}"; do
			rsync_exclude=("${rsync_exclude[@]}" --exclude="$f")
		done

		#info "running push to $target"
		$rsync $g_rsync_opts ${rsync_exclude[@]} ${rsync_include[@]} -e ssh "${remote_user}@${remote_host}:${remote_dir}"

		run_project_hook_if_exists after push
		run_global_hook_if_exists after push
	)
}

project_ssh() {
	local target="$1"; shift

	if [[ -z $target ]]; then
		throw "invalid usage"
	fi

	if ! in_project; then
		throw "$err_not_project"
	fi

	if ! project_has_target "$target"; then
		throw "target remote not defined (see \`$g_rctl config\`)"
	fi

	(
		local args=("$@")
		local ssh_opts=()
		local project="$(find_project_root)"
		cd "$project" # required for rsync

		source "$(find_project_root)/$g_project_config"

		local remote="remote_$target"
		local remote_host="$(eval echo \"\${$remote[0]}\")"
		local remote_user="$(eval echo \"\${$remote[1]}\")"
		local remote_dir="$(eval echo \"\${$remote[2]}\")"

		run_global_hook_if_exists before ssh
		run_project_hook_if_exists before ssh

		if [[ "${#args[@]}" -gt 0 ]]; then
			#info "running ssh on $target"
		fi
		ssh "${remote_user}@${remote_host}" "${ssh_opts[@]}" "${args[@]}"

		run_project_hook_if_exists after ssh
		run_global_hook_if_exists after ssh
	)
}

project_run() {
	local command="$1"; shift
	local project=""
	local command_file
	local is_project_command

	if [[ ! $command =~ ^[a-z_][a-z0-9_-]*$ ]]; then
		throw "invalid command name"
	fi

	if ! in_project; then
		command_file="$g_main_commands_dir/${command}.bash"

		if [[ ! -f $command_file ]]; then
			throw "invalid global command"
		fi

		run_global_hook_if_exists before "$command"

		source "$command_file"
		#info "running global command: $command"
		command_run

		run_global_hook_if_exists after "$command"

		exit $OK
	fi

	project="$(find_project_root)"

	command_file="$project/$g_project_commands_dir/${command}.bash"
	is_project_command=true

	if [[ ! -f $command_file ]]; then
		command_file="$g_main_commands_dir/${command}.bash"
		is_project_command=false

		if [[ ! -f $command_file ]]; then
			throw "invalid command"
		fi
	fi

	(
		cd "$project"

		source "$(find_project_root)/$g_project_config"

		run_global_hook_if_exists before "$command"
		run_project_hook_if_exists before "$command"

		source "$command_file"

		if $is_project_command; then
			#info "running project command: $command"
		else
			#info "running global command: $command"
		fi

		command_run "$@"

		run_project_hook_if_exists after "$command"
		run_global_hook_if_exists after "$command"
	)
}


# autocomplete
#-------------------------------------------------------------------------------

autocomplete() {
	local arg="$1"; shift

	local main_commands="$(list_commands "$g_main_commands_dir")"
	local project="$(find_project_root "$PWD")"
	local project_commands=""

	if in_project; then
		project_commands="$(list_commands "$project/$g_project_commands_dir")"
	fi

	case $arg in
		"")
			echo help

			if [[ -n $main_commands ]]; then
				for cmd in "$main_commands"; do
					echo "$cmd"
				done
			fi

			if ! in_project && in_initializable_project; then
				echo init
			fi

			if in_project; then
				echo ssh
				echo push
				echo config
				echo edit-command
				echo edit-hook

				if [[ -n $project_commands ]]; then
					for cmd in "$project_commands"; do
						echo "$cmd"
					done
				fi
			fi
			;;

		push)
			project_list_targets
			;;

		ssh)
			project_list_targets
			;;

		edit-command)
			if [[ -n $project_commands ]]; then
				for cmd in "$project_commands"; do
					echo "$cmd"
				done
			fi
			;;

		edit-hook)
			when="$1"; shift

			case $when in
				"")
					echo before
					echo after
					;;
				before|after)
					echo push
					echo ssh
					for cmd in "$project_commands"; do
						echo "$cmd"
					done
					;;
			esac
			;;

		*)
			if [[ -n $project_commands ]]; then
				for command in "$project_commands"; do
					if [[ $arg == $command ]]; then
						command_file="$project/$g_project_commands_dir/${command}.bash"
						source "$command_file"
						command_autocomplete "$@"
					fi
				done
			fi
			;;
	esac
}


# run
#-------------------------------------------------------------------------------

main() {
	rctl_setup

	local action="$1"; shift

	case "$action" in
		init)
			project_init
			;;

		push)
			local target="$1"; shift
			local args=("$@")

			project_push "$target" "${args[@]}"
			;;

		ssh)
			local target="$1"; shift
			local args=("$@")

			project_ssh "$target" "${args[@]}"
			;;

		config)
			project_edit_config
			;;

		edit-command)
			local command="$1"

			project_edit_command "$command"
			;;

		edit-hook)
			local when="$1"
			local command="$2"

			project_edit_hook "$when" "$command"
			;;

		help)
			help
			;;

		---)
			autocomplete "$@"
			;;

		"")
			throw "please specify a command (see \`$g_rctl help\`)"
			;;

		*)
			project_run "$action" "$@"
			;;
	esac

	exit $OK
}

main "$@"
