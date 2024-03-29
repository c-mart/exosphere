module Helpers.ExoSetupStatus exposing
    ( exoSetupStatusToStr
    , parseConsoleLogExoSetupStatus
    )

import Json.Decode
import Time
import Types.Types exposing (ExoSetupStatus(..))


parseConsoleLogExoSetupStatus : ExoSetupStatus -> String -> Time.Posix -> Time.Posix -> ExoSetupStatus
parseConsoleLogExoSetupStatus oldExoSetupStatus consoleLog serverCreatedTime currentTime =
    let
        logLines =
            String.split "\n" consoleLog

        decodedData =
            logLines
                -- Throw out anything before the start of a JSON object on a given line
                |> List.map
                    (\line ->
                        String.indexes "{" line
                            |> List.head
                            |> Maybe.map (\index -> String.dropLeft index line)
                            |> Maybe.withDefault line
                    )
                -- Throw out anything after the end of a JSON object on a given line
                |> List.map
                    (\line ->
                        String.indexes "}" line
                            |> List.reverse
                            |> List.head
                            |> Maybe.map (\index -> String.left (index + 1) line)
                            |> Maybe.withDefault line
                    )
                |> List.map (Json.Decode.decodeString decodeLogLine)
                |> List.map Result.toMaybe
                |> List.filterMap identity

        latestStatus =
            decodedData
                |> List.reverse
                |> List.head
                |> Maybe.withDefault oldExoSetupStatus

        nonTerminalStatuses =
            [ ExoSetupWaiting, ExoSetupRunning ]

        statusIsNonTerminal =
            List.member latestStatus nonTerminalStatuses

        serverTooOldForNonTerminalStatus =
            Time.posixToMillis serverCreatedTime
                -- 2 hours
                + 7200000
                < Time.posixToMillis currentTime

        finalStatus =
            if statusIsNonTerminal && serverTooOldForNonTerminalStatus then
                ExoSetupTimeout

            else
                latestStatus
    in
    finalStatus


exoSetupStatusToStr : ExoSetupStatus -> String
exoSetupStatusToStr status =
    case status of
        ExoSetupWaiting ->
            "waiting"

        ExoSetupRunning ->
            "running"

        ExoSetupComplete ->
            "complete"

        ExoSetupTimeout ->
            "timeout"

        ExoSetupError ->
            "error"

        ExoSetupUnknown ->
            "unknown"


decodeLogLine : Json.Decode.Decoder ExoSetupStatus
decodeLogLine =
    let
        strtoExoSetupStatus str =
            case str of
                "waiting" ->
                    Json.Decode.succeed ExoSetupWaiting

                "running" ->
                    Json.Decode.succeed ExoSetupRunning

                "complete" ->
                    Json.Decode.succeed ExoSetupComplete

                "timeout" ->
                    Json.Decode.succeed ExoSetupTimeout

                "error" ->
                    Json.Decode.succeed ExoSetupError

                "unknown" ->
                    Json.Decode.succeed ExoSetupUnknown

                _ ->
                    Json.Decode.fail "no matching string"
    in
    Json.Decode.field "exoSetup" Json.Decode.string
        |> Json.Decode.andThen strtoExoSetupStatus
