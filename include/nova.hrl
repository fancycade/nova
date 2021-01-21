-include_lib("kernel/include/logger.hrl").

-define(TERM_RED, "\e[31m").

-define(TERM_GREEN, "\e[32m").

-define(TERM_YELLOW, "\e[33m").

-define(TERM_BLUE, "\e[34m").

-define(TERM_BOLD, "\e[1m").

-define(TERM_RESET, "\e[m").

-define(DEBUG(M),
        ?LOG(debug, ((?TERM_BLUE) ++ M ++ (?TERM_RESET)))).

-define(DEBUG(M, Meta),
        ?LOG(debug, ((?TERM_BLUE) ++ M ++ (?TERM_RESET)),
             Meta)).

-define(INFO(M),
        ?LOG(info, ((?TERM_GREEN) ++ M ++ (?TERM_RESET)))).

-define(INFO(M, Meta),
        ?LOG(info, ((?TERM_GREEN) ++ M ++ (?TERM_RESET)),
             Meta)).

-define(WARNING(M),
        ?LOG(warning, ((?TERM_YELLOW) ++ M ++ (?TERM_RESET)))).

-define(WARNING(M, Meta),
        ?LOG(warning, ((?TERM_YELLOW) ++ M ++ (?TERM_RESET)),
             Meta)).

-define(ERROR(M),
        ?LOG(error, ((?TERM_RED) ++ M ++ (?TERM_RESET)))).

-define(ERROR(M, Meta),
        ?LOG(error, ((?TERM_RED) ++ M ++ (?TERM_RESET)), Meta)).

%% Meta levels
-define(DEPRECATION(M),
        ?LOG(warning,
             ((?TERM_YELLOW) ++
                  (?TERM_BOLD) ++
                      "DEPRECATION WARNING! " ++
                          (?TERM_RESET) ++
                              (?TERM_YELLOW) ++ M ++ (?TERM_RESET)))).

-define(DEPRECATED(M),
        ?LOG(error,
             ((?TERM_RED) ++
                  (?TERM_BOLD) ++
                      "DEPRECATION ERROR!!! " ++
                          (?TERM_RESET) ++ (?TERM_RED) ++ M ++ (?TERM_RESET)))).
