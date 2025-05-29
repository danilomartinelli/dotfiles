#compdef bws

autoload -U is-at-least

_bws() {
    typeset -A opt_args
    typeset -a _arguments_options
    local ret=1

    if is-at-least 5.2; then
        _arguments_options=(-s -S -C)
    else
        _arguments_options=(-s -C)
    fi

    local context curcontext="$curcontext" state line
    _arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
'-V[Print version]' \
'--version[Print version]' \
":: :_bws_commands" \
"*::: :->bws" \
&& ret=0
    case $state in
    (bws)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-command-$line[1]:"
        case $line[1] in
            (config)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-d[]' \
'--delete[]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
'::name:(server-base server-api server-identity state-file-dir)' \
'::value:' \
&& ret=0
;;
(completions)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
'::shell:(bash elvish fish powershell zsh)' \
&& ret=0
;;
(project)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
":: :_bws__project_commands" \
"*::: :->project" \
&& ret=0

    case $state in
    (project)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-project-command-$line[1]:"
        case $line[1] in
            (create)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
':name:' \
&& ret=0
;;
(delete)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
'*::project_ids:' \
&& ret=0
;;
(edit)
_arguments "${_arguments_options[@]}" \
'--name=[]:NAME: ' \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
':project_id:' \
&& ret=0
;;
(get)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
':project_id:' \
&& ret=0
;;
(list)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
":: :_bws__project__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-project-help-command-$line[1]:"
        case $line[1] in
            (create)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(delete)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(edit)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(get)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(list)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
;;
(secret)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
":: :_bws__secret_commands" \
"*::: :->secret" \
&& ret=0

    case $state in
    (secret)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-secret-command-$line[1]:"
        case $line[1] in
            (create)
_arguments "${_arguments_options[@]}" \
'--note=[An optional note to add to the secret]:NOTE: ' \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
':key:' \
':value:' \
':project_id -- The ID of the project this secret will be added to:' \
&& ret=0
;;
(delete)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
'*::secret_ids:' \
&& ret=0
;;
(edit)
_arguments "${_arguments_options[@]}" \
'--key=[]:KEY: ' \
'--value=[]:VALUE: ' \
'--note=[]:NOTE: ' \
'--project-id=[]:PROJECT_ID: ' \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
':secret_id:' \
&& ret=0
;;
(get)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
':secret_id:' \
&& ret=0
;;
(list)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
'::project_id:' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
":: :_bws__secret__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-secret-help-command-$line[1]:"
        case $line[1] in
            (create)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(delete)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(edit)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(get)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(list)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
;;
(create)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
":: :_bws__create_commands" \
"*::: :->create" \
&& ret=0

    case $state in
    (create)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-create-command-$line[1]:"
        case $line[1] in
            (project)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
':name:' \
&& ret=0
;;
(secret)
_arguments "${_arguments_options[@]}" \
'--note=[An optional note to add to the secret]:NOTE: ' \
'--project-id=[The ID of the project this secret will be added to]:PROJECT_ID: ' \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
':key:' \
':value:' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
":: :_bws__create__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-create-help-command-$line[1]:"
        case $line[1] in
            (project)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(secret)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
;;
(delete)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
":: :_bws__delete_commands" \
"*::: :->delete" \
&& ret=0

    case $state in
    (delete)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-delete-command-$line[1]:"
        case $line[1] in
            (project)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
'*::project_ids:' \
&& ret=0
;;
(secret)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
'*::secret_ids:' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
":: :_bws__delete__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-delete-help-command-$line[1]:"
        case $line[1] in
            (project)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(secret)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
;;
(edit)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
":: :_bws__edit_commands" \
"*::: :->edit" \
&& ret=0

    case $state in
    (edit)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-edit-command-$line[1]:"
        case $line[1] in
            (project)
_arguments "${_arguments_options[@]}" \
'--name=[]:NAME: ' \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
':project_id:' \
&& ret=0
;;
(secret)
_arguments "${_arguments_options[@]}" \
'--key=[]:KEY: ' \
'--value=[]:VALUE: ' \
'--note=[]:NOTE: ' \
'--project-id=[]:PROJECT_ID: ' \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
':secret_id:' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
":: :_bws__edit__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-edit-help-command-$line[1]:"
        case $line[1] in
            (project)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(secret)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
;;
(get)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
":: :_bws__get_commands" \
"*::: :->get" \
&& ret=0

    case $state in
    (get)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-get-command-$line[1]:"
        case $line[1] in
            (project)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
':project_id:' \
&& ret=0
;;
(secret)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
':secret_id:' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
":: :_bws__get__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-get-help-command-$line[1]:"
        case $line[1] in
            (project)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(secret)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
;;
(list)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
":: :_bws__list_commands" \
"*::: :->list" \
&& ret=0

    case $state in
    (list)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-list-command-$line[1]:"
        case $line[1] in
            (projects)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
&& ret=0
;;
(secrets)
_arguments "${_arguments_options[@]}" \
'-o+[Output format]:OUTPUT:(json yaml env table tsv none)' \
'--output=[Output format]:OUTPUT:(json yaml env table tsv none)' \
'-c+[Use colors in the output]:COLOR:(no yes auto)' \
'--color=[Use colors in the output]:COLOR:(no yes auto)' \
'-t+[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'--access-token=[Specify access token for the machine account]:ACCESS_TOKEN: ' \
'-f+[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'--config-file=[\[default\: ~/.bws/config\] Config file to use]:CONFIG_FILE:_files' \
'-p+[Profile to use from the config file]:PROFILE: ' \
'--profile=[Profile to use from the config file]:PROFILE: ' \
'-u+[Override the server URL from the config file]:SERVER_URL: ' \
'--server-url=[Override the server URL from the config file]:SERVER_URL: ' \
'-h[Print help]' \
'--help[Print help]' \
'::project_id:' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
":: :_bws__list__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-list-help-command-$line[1]:"
        case $line[1] in
            (projects)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(secrets)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
;;
(help)
_arguments "${_arguments_options[@]}" \
":: :_bws__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-help-command-$line[1]:"
        case $line[1] in
            (config)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(completions)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(project)
_arguments "${_arguments_options[@]}" \
":: :_bws__help__project_commands" \
"*::: :->project" \
&& ret=0

    case $state in
    (project)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-help-project-command-$line[1]:"
        case $line[1] in
            (create)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(delete)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(edit)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(get)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(list)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
(secret)
_arguments "${_arguments_options[@]}" \
":: :_bws__help__secret_commands" \
"*::: :->secret" \
&& ret=0

    case $state in
    (secret)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-help-secret-command-$line[1]:"
        case $line[1] in
            (create)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(delete)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(edit)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(get)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(list)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
(create)
_arguments "${_arguments_options[@]}" \
":: :_bws__help__create_commands" \
"*::: :->create" \
&& ret=0

    case $state in
    (create)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-help-create-command-$line[1]:"
        case $line[1] in
            (project)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(secret)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
(delete)
_arguments "${_arguments_options[@]}" \
":: :_bws__help__delete_commands" \
"*::: :->delete" \
&& ret=0

    case $state in
    (delete)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-help-delete-command-$line[1]:"
        case $line[1] in
            (project)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(secret)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
(edit)
_arguments "${_arguments_options[@]}" \
":: :_bws__help__edit_commands" \
"*::: :->edit" \
&& ret=0

    case $state in
    (edit)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-help-edit-command-$line[1]:"
        case $line[1] in
            (project)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(secret)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
(get)
_arguments "${_arguments_options[@]}" \
":: :_bws__help__get_commands" \
"*::: :->get" \
&& ret=0

    case $state in
    (get)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-help-get-command-$line[1]:"
        case $line[1] in
            (project)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(secret)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
(list)
_arguments "${_arguments_options[@]}" \
":: :_bws__help__list_commands" \
"*::: :->list" \
&& ret=0

    case $state in
    (list)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:bws-help-list-command-$line[1]:"
        case $line[1] in
            (projects)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(secrets)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
(help)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
}

(( $+functions[_bws_commands] )) ||
_bws_commands() {
    local commands; commands=(
'config:' \
'completions:' \
'project:' \
'secret:' \
'create:' \
'delete:' \
'edit:' \
'get:' \
'list:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws commands' commands "$@"
}
(( $+functions[_bws__completions_commands] )) ||
_bws__completions_commands() {
    local commands; commands=()
    _describe -t commands 'bws completions commands' commands "$@"
}
(( $+functions[_bws__help__completions_commands] )) ||
_bws__help__completions_commands() {
    local commands; commands=()
    _describe -t commands 'bws help completions commands' commands "$@"
}
(( $+functions[_bws__config_commands] )) ||
_bws__config_commands() {
    local commands; commands=()
    _describe -t commands 'bws config commands' commands "$@"
}
(( $+functions[_bws__help__config_commands] )) ||
_bws__help__config_commands() {
    local commands; commands=()
    _describe -t commands 'bws help config commands' commands "$@"
}
(( $+functions[_bws__create_commands] )) ||
_bws__create_commands() {
    local commands; commands=(
'project:' \
'secret:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws create commands' commands "$@"
}
(( $+functions[_bws__help__create_commands] )) ||
_bws__help__create_commands() {
    local commands; commands=(
'project:' \
'secret:' \
    )
    _describe -t commands 'bws help create commands' commands "$@"
}
(( $+functions[_bws__help__project__create_commands] )) ||
_bws__help__project__create_commands() {
    local commands; commands=()
    _describe -t commands 'bws help project create commands' commands "$@"
}
(( $+functions[_bws__help__secret__create_commands] )) ||
_bws__help__secret__create_commands() {
    local commands; commands=()
    _describe -t commands 'bws help secret create commands' commands "$@"
}
(( $+functions[_bws__project__create_commands] )) ||
_bws__project__create_commands() {
    local commands; commands=()
    _describe -t commands 'bws project create commands' commands "$@"
}
(( $+functions[_bws__project__help__create_commands] )) ||
_bws__project__help__create_commands() {
    local commands; commands=()
    _describe -t commands 'bws project help create commands' commands "$@"
}
(( $+functions[_bws__secret__create_commands] )) ||
_bws__secret__create_commands() {
    local commands; commands=()
    _describe -t commands 'bws secret create commands' commands "$@"
}
(( $+functions[_bws__secret__help__create_commands] )) ||
_bws__secret__help__create_commands() {
    local commands; commands=()
    _describe -t commands 'bws secret help create commands' commands "$@"
}
(( $+functions[_bws__delete_commands] )) ||
_bws__delete_commands() {
    local commands; commands=(
'project:' \
'secret:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws delete commands' commands "$@"
}
(( $+functions[_bws__help__delete_commands] )) ||
_bws__help__delete_commands() {
    local commands; commands=(
'project:' \
'secret:' \
    )
    _describe -t commands 'bws help delete commands' commands "$@"
}
(( $+functions[_bws__help__project__delete_commands] )) ||
_bws__help__project__delete_commands() {
    local commands; commands=()
    _describe -t commands 'bws help project delete commands' commands "$@"
}
(( $+functions[_bws__help__secret__delete_commands] )) ||
_bws__help__secret__delete_commands() {
    local commands; commands=()
    _describe -t commands 'bws help secret delete commands' commands "$@"
}
(( $+functions[_bws__project__delete_commands] )) ||
_bws__project__delete_commands() {
    local commands; commands=()
    _describe -t commands 'bws project delete commands' commands "$@"
}
(( $+functions[_bws__project__help__delete_commands] )) ||
_bws__project__help__delete_commands() {
    local commands; commands=()
    _describe -t commands 'bws project help delete commands' commands "$@"
}
(( $+functions[_bws__secret__delete_commands] )) ||
_bws__secret__delete_commands() {
    local commands; commands=()
    _describe -t commands 'bws secret delete commands' commands "$@"
}
(( $+functions[_bws__secret__help__delete_commands] )) ||
_bws__secret__help__delete_commands() {
    local commands; commands=()
    _describe -t commands 'bws secret help delete commands' commands "$@"
}
(( $+functions[_bws__edit_commands] )) ||
_bws__edit_commands() {
    local commands; commands=(
'project:' \
'secret:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws edit commands' commands "$@"
}
(( $+functions[_bws__help__edit_commands] )) ||
_bws__help__edit_commands() {
    local commands; commands=(
'project:' \
'secret:' \
    )
    _describe -t commands 'bws help edit commands' commands "$@"
}
(( $+functions[_bws__help__project__edit_commands] )) ||
_bws__help__project__edit_commands() {
    local commands; commands=()
    _describe -t commands 'bws help project edit commands' commands "$@"
}
(( $+functions[_bws__help__secret__edit_commands] )) ||
_bws__help__secret__edit_commands() {
    local commands; commands=()
    _describe -t commands 'bws help secret edit commands' commands "$@"
}
(( $+functions[_bws__project__edit_commands] )) ||
_bws__project__edit_commands() {
    local commands; commands=()
    _describe -t commands 'bws project edit commands' commands "$@"
}
(( $+functions[_bws__project__help__edit_commands] )) ||
_bws__project__help__edit_commands() {
    local commands; commands=()
    _describe -t commands 'bws project help edit commands' commands "$@"
}
(( $+functions[_bws__secret__edit_commands] )) ||
_bws__secret__edit_commands() {
    local commands; commands=()
    _describe -t commands 'bws secret edit commands' commands "$@"
}
(( $+functions[_bws__secret__help__edit_commands] )) ||
_bws__secret__help__edit_commands() {
    local commands; commands=()
    _describe -t commands 'bws secret help edit commands' commands "$@"
}
(( $+functions[_bws__get_commands] )) ||
_bws__get_commands() {
    local commands; commands=(
'project:' \
'secret:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws get commands' commands "$@"
}
(( $+functions[_bws__help__get_commands] )) ||
_bws__help__get_commands() {
    local commands; commands=(
'project:' \
'secret:' \
    )
    _describe -t commands 'bws help get commands' commands "$@"
}
(( $+functions[_bws__help__project__get_commands] )) ||
_bws__help__project__get_commands() {
    local commands; commands=()
    _describe -t commands 'bws help project get commands' commands "$@"
}
(( $+functions[_bws__help__secret__get_commands] )) ||
_bws__help__secret__get_commands() {
    local commands; commands=()
    _describe -t commands 'bws help secret get commands' commands "$@"
}
(( $+functions[_bws__project__get_commands] )) ||
_bws__project__get_commands() {
    local commands; commands=()
    _describe -t commands 'bws project get commands' commands "$@"
}
(( $+functions[_bws__project__help__get_commands] )) ||
_bws__project__help__get_commands() {
    local commands; commands=()
    _describe -t commands 'bws project help get commands' commands "$@"
}
(( $+functions[_bws__secret__get_commands] )) ||
_bws__secret__get_commands() {
    local commands; commands=()
    _describe -t commands 'bws secret get commands' commands "$@"
}
(( $+functions[_bws__secret__help__get_commands] )) ||
_bws__secret__help__get_commands() {
    local commands; commands=()
    _describe -t commands 'bws secret help get commands' commands "$@"
}
(( $+functions[_bws__create__help_commands] )) ||
_bws__create__help_commands() {
    local commands; commands=(
'project:' \
'secret:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws create help commands' commands "$@"
}
(( $+functions[_bws__create__help__help_commands] )) ||
_bws__create__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'bws create help help commands' commands "$@"
}
(( $+functions[_bws__delete__help_commands] )) ||
_bws__delete__help_commands() {
    local commands; commands=(
'project:' \
'secret:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws delete help commands' commands "$@"
}
(( $+functions[_bws__delete__help__help_commands] )) ||
_bws__delete__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'bws delete help help commands' commands "$@"
}
(( $+functions[_bws__edit__help_commands] )) ||
_bws__edit__help_commands() {
    local commands; commands=(
'project:' \
'secret:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws edit help commands' commands "$@"
}
(( $+functions[_bws__edit__help__help_commands] )) ||
_bws__edit__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'bws edit help help commands' commands "$@"
}
(( $+functions[_bws__get__help_commands] )) ||
_bws__get__help_commands() {
    local commands; commands=(
'project:' \
'secret:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws get help commands' commands "$@"
}
(( $+functions[_bws__get__help__help_commands] )) ||
_bws__get__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'bws get help help commands' commands "$@"
}
(( $+functions[_bws__help_commands] )) ||
_bws__help_commands() {
    local commands; commands=(
'config:' \
'completions:' \
'project:' \
'secret:' \
'create:' \
'delete:' \
'edit:' \
'get:' \
'list:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws help commands' commands "$@"
}
(( $+functions[_bws__help__help_commands] )) ||
_bws__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'bws help help commands' commands "$@"
}
(( $+functions[_bws__list__help_commands] )) ||
_bws__list__help_commands() {
    local commands; commands=(
'projects:' \
'secrets:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws list help commands' commands "$@"
}
(( $+functions[_bws__list__help__help_commands] )) ||
_bws__list__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'bws list help help commands' commands "$@"
}
(( $+functions[_bws__project__help_commands] )) ||
_bws__project__help_commands() {
    local commands; commands=(
'create:' \
'delete:' \
'edit:' \
'get:' \
'list:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws project help commands' commands "$@"
}
(( $+functions[_bws__project__help__help_commands] )) ||
_bws__project__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'bws project help help commands' commands "$@"
}
(( $+functions[_bws__secret__help_commands] )) ||
_bws__secret__help_commands() {
    local commands; commands=(
'create:' \
'delete:' \
'edit:' \
'get:' \
'list:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws secret help commands' commands "$@"
}
(( $+functions[_bws__secret__help__help_commands] )) ||
_bws__secret__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'bws secret help help commands' commands "$@"
}
(( $+functions[_bws__help__list_commands] )) ||
_bws__help__list_commands() {
    local commands; commands=(
'projects:' \
'secrets:' \
    )
    _describe -t commands 'bws help list commands' commands "$@"
}
(( $+functions[_bws__help__project__list_commands] )) ||
_bws__help__project__list_commands() {
    local commands; commands=()
    _describe -t commands 'bws help project list commands' commands "$@"
}
(( $+functions[_bws__help__secret__list_commands] )) ||
_bws__help__secret__list_commands() {
    local commands; commands=()
    _describe -t commands 'bws help secret list commands' commands "$@"
}
(( $+functions[_bws__list_commands] )) ||
_bws__list_commands() {
    local commands; commands=(
'projects:' \
'secrets:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws list commands' commands "$@"
}
(( $+functions[_bws__project__help__list_commands] )) ||
_bws__project__help__list_commands() {
    local commands; commands=()
    _describe -t commands 'bws project help list commands' commands "$@"
}
(( $+functions[_bws__project__list_commands] )) ||
_bws__project__list_commands() {
    local commands; commands=()
    _describe -t commands 'bws project list commands' commands "$@"
}
(( $+functions[_bws__secret__help__list_commands] )) ||
_bws__secret__help__list_commands() {
    local commands; commands=()
    _describe -t commands 'bws secret help list commands' commands "$@"
}
(( $+functions[_bws__secret__list_commands] )) ||
_bws__secret__list_commands() {
    local commands; commands=()
    _describe -t commands 'bws secret list commands' commands "$@"
}
(( $+functions[_bws__create__help__project_commands] )) ||
_bws__create__help__project_commands() {
    local commands; commands=()
    _describe -t commands 'bws create help project commands' commands "$@"
}
(( $+functions[_bws__create__project_commands] )) ||
_bws__create__project_commands() {
    local commands; commands=()
    _describe -t commands 'bws create project commands' commands "$@"
}
(( $+functions[_bws__delete__help__project_commands] )) ||
_bws__delete__help__project_commands() {
    local commands; commands=()
    _describe -t commands 'bws delete help project commands' commands "$@"
}
(( $+functions[_bws__delete__project_commands] )) ||
_bws__delete__project_commands() {
    local commands; commands=()
    _describe -t commands 'bws delete project commands' commands "$@"
}
(( $+functions[_bws__edit__help__project_commands] )) ||
_bws__edit__help__project_commands() {
    local commands; commands=()
    _describe -t commands 'bws edit help project commands' commands "$@"
}
(( $+functions[_bws__edit__project_commands] )) ||
_bws__edit__project_commands() {
    local commands; commands=()
    _describe -t commands 'bws edit project commands' commands "$@"
}
(( $+functions[_bws__get__help__project_commands] )) ||
_bws__get__help__project_commands() {
    local commands; commands=()
    _describe -t commands 'bws get help project commands' commands "$@"
}
(( $+functions[_bws__get__project_commands] )) ||
_bws__get__project_commands() {
    local commands; commands=()
    _describe -t commands 'bws get project commands' commands "$@"
}
(( $+functions[_bws__help__create__project_commands] )) ||
_bws__help__create__project_commands() {
    local commands; commands=()
    _describe -t commands 'bws help create project commands' commands "$@"
}
(( $+functions[_bws__help__delete__project_commands] )) ||
_bws__help__delete__project_commands() {
    local commands; commands=()
    _describe -t commands 'bws help delete project commands' commands "$@"
}
(( $+functions[_bws__help__edit__project_commands] )) ||
_bws__help__edit__project_commands() {
    local commands; commands=()
    _describe -t commands 'bws help edit project commands' commands "$@"
}
(( $+functions[_bws__help__get__project_commands] )) ||
_bws__help__get__project_commands() {
    local commands; commands=()
    _describe -t commands 'bws help get project commands' commands "$@"
}
(( $+functions[_bws__help__project_commands] )) ||
_bws__help__project_commands() {
    local commands; commands=(
'create:' \
'delete:' \
'edit:' \
'get:' \
'list:' \
    )
    _describe -t commands 'bws help project commands' commands "$@"
}
(( $+functions[_bws__project_commands] )) ||
_bws__project_commands() {
    local commands; commands=(
'create:' \
'delete:' \
'edit:' \
'get:' \
'list:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws project commands' commands "$@"
}
(( $+functions[_bws__help__list__projects_commands] )) ||
_bws__help__list__projects_commands() {
    local commands; commands=()
    _describe -t commands 'bws help list projects commands' commands "$@"
}
(( $+functions[_bws__list__help__projects_commands] )) ||
_bws__list__help__projects_commands() {
    local commands; commands=()
    _describe -t commands 'bws list help projects commands' commands "$@"
}
(( $+functions[_bws__list__projects_commands] )) ||
_bws__list__projects_commands() {
    local commands; commands=()
    _describe -t commands 'bws list projects commands' commands "$@"
}
(( $+functions[_bws__create__help__secret_commands] )) ||
_bws__create__help__secret_commands() {
    local commands; commands=()
    _describe -t commands 'bws create help secret commands' commands "$@"
}
(( $+functions[_bws__create__secret_commands] )) ||
_bws__create__secret_commands() {
    local commands; commands=()
    _describe -t commands 'bws create secret commands' commands "$@"
}
(( $+functions[_bws__delete__help__secret_commands] )) ||
_bws__delete__help__secret_commands() {
    local commands; commands=()
    _describe -t commands 'bws delete help secret commands' commands "$@"
}
(( $+functions[_bws__delete__secret_commands] )) ||
_bws__delete__secret_commands() {
    local commands; commands=()
    _describe -t commands 'bws delete secret commands' commands "$@"
}
(( $+functions[_bws__edit__help__secret_commands] )) ||
_bws__edit__help__secret_commands() {
    local commands; commands=()
    _describe -t commands 'bws edit help secret commands' commands "$@"
}
(( $+functions[_bws__edit__secret_commands] )) ||
_bws__edit__secret_commands() {
    local commands; commands=()
    _describe -t commands 'bws edit secret commands' commands "$@"
}
(( $+functions[_bws__get__help__secret_commands] )) ||
_bws__get__help__secret_commands() {
    local commands; commands=()
    _describe -t commands 'bws get help secret commands' commands "$@"
}
(( $+functions[_bws__get__secret_commands] )) ||
_bws__get__secret_commands() {
    local commands; commands=()
    _describe -t commands 'bws get secret commands' commands "$@"
}
(( $+functions[_bws__help__create__secret_commands] )) ||
_bws__help__create__secret_commands() {
    local commands; commands=()
    _describe -t commands 'bws help create secret commands' commands "$@"
}
(( $+functions[_bws__help__delete__secret_commands] )) ||
_bws__help__delete__secret_commands() {
    local commands; commands=()
    _describe -t commands 'bws help delete secret commands' commands "$@"
}
(( $+functions[_bws__help__edit__secret_commands] )) ||
_bws__help__edit__secret_commands() {
    local commands; commands=()
    _describe -t commands 'bws help edit secret commands' commands "$@"
}
(( $+functions[_bws__help__get__secret_commands] )) ||
_bws__help__get__secret_commands() {
    local commands; commands=()
    _describe -t commands 'bws help get secret commands' commands "$@"
}
(( $+functions[_bws__help__secret_commands] )) ||
_bws__help__secret_commands() {
    local commands; commands=(
'create:' \
'delete:' \
'edit:' \
'get:' \
'list:' \
    )
    _describe -t commands 'bws help secret commands' commands "$@"
}
(( $+functions[_bws__secret_commands] )) ||
_bws__secret_commands() {
    local commands; commands=(
'create:' \
'delete:' \
'edit:' \
'get:' \
'list:' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'bws secret commands' commands "$@"
}
(( $+functions[_bws__help__list__secrets_commands] )) ||
_bws__help__list__secrets_commands() {
    local commands; commands=()
    _describe -t commands 'bws help list secrets commands' commands "$@"
}
(( $+functions[_bws__list__help__secrets_commands] )) ||
_bws__list__help__secrets_commands() {
    local commands; commands=()
    _describe -t commands 'bws list help secrets commands' commands "$@"
}
(( $+functions[_bws__list__secrets_commands] )) ||
_bws__list__secrets_commands() {
    local commands; commands=()
    _describe -t commands 'bws list secrets commands' commands "$@"
}

if [ "$funcstack[1]" = "_bws" ]; then
    _bws "$@"
else
    compdef _bws bws
fi
