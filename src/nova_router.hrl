%% Method, Module, Function-record
-record(mmf, {
              method = '_' :: binary() | '_',
              app :: atom(),
              module :: atom(),
              function :: atom(),
              secure = false :: false | {Mod :: atom(), Fun :: atom()},
              extra_state :: any(),
              protocol = http :: http | static | ws
             }).
