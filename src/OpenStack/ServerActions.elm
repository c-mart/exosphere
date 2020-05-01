module OpenStack.ServerActions exposing
    ( ActionType(..)
    , ServerAction
    , getAllowed
    )

import Error exposing (ErrorContext, ErrorLevel(..))
import Framework.Modifier as Modifier
import Helpers.Helpers as Helpers
import Http
import Json.Encode
import OpenStack.Types as OSTypes
import Rest.Helpers exposing (openstackCredentialedRequest, resultToMsg)
import Rest.Nova
import Types.Types
    exposing
        ( HttpRequestMethod(..)
        , Msg(..)
        , Project
        , ProjectIdentifier
        , ProjectSpecificMsgConstructor(..)
        , ProjectViewConstructor(..)
        , Server
        )


getAllowed : OSTypes.ServerStatus -> OSTypes.ServerLockStatus -> List ServerAction
getAllowed serverStatus serverLockStatus =
    let
        allowedByServerStatus action =
            case action.allowedStatuses of
                Nothing ->
                    True

                Just allowedStatuses ->
                    List.member serverStatus allowedStatuses

        allowedByLockStatus action =
            case action.allowedLockStatus of
                Nothing ->
                    True

                Just allowedLockStatus_ ->
                    serverLockStatus == allowedLockStatus_
    in
    actions
        |> List.filter allowedByServerStatus
        |> List.filter allowedByLockStatus


type alias ServerAction =
    { name : String
    , description : String
    , allowedStatuses : Maybe (List OSTypes.ServerStatus)
    , allowedLockStatus : Maybe OSTypes.ServerLockStatus
    , action : ActionType
    , selectMods : List Modifier.Modifier
    , targetStatus : Maybe (List OSTypes.ServerStatus)
    , confirmable : Bool
    }


type ActionType
    = CmdAction (Project -> Server -> Cmd Msg)
    | UpdateAction (ProjectIdentifier -> Server -> Msg)


actions : List ServerAction
actions =
    [ { name = "Lock"
      , description = "Prevent further server actions until it is unlocked"
      , allowedStatuses = Nothing
      , allowedLockStatus = Just OSTypes.ServerUnlocked
      , action =
            CmdAction <|
                doAction (Json.Encode.object [ ( "lock", Json.Encode.null ) ])
      , selectMods = []
      , targetStatus = Nothing
      , confirmable = False
      }
    , { name = "Unlock"
      , description = "Allow further server actions"
      , allowedStatuses = Nothing
      , allowedLockStatus = Just OSTypes.ServerLocked
      , action =
            CmdAction <|
                doAction (Json.Encode.object [ ( "unlock", Json.Encode.null ) ])
      , selectMods = [ Modifier.Warning ]
      , targetStatus = Nothing
      , confirmable = False
      }
    , { name = "Start"
      , description = "Start stopped server"
      , allowedStatuses = Just [ OSTypes.ServerStopped, OSTypes.ServerShutoff ]
      , allowedLockStatus = Just OSTypes.ServerUnlocked
      , action =
            CmdAction <|
                doAction <|
                    Json.Encode.object [ ( "os-start", Json.Encode.null ) ]
      , selectMods = [ Modifier.Primary ]
      , targetStatus = Just [ OSTypes.ServerActive ]
      , confirmable = False
      }
    , { name = "Unpause"
      , description = "Restore paused server"
      , allowedStatuses = Just [ OSTypes.ServerPaused ]
      , allowedLockStatus = Just OSTypes.ServerUnlocked
      , action =
            CmdAction <|
                doAction <|
                    Json.Encode.object [ ( "unpause", Json.Encode.null ) ]
      , selectMods = [ Modifier.Primary ]
      , targetStatus = Just [ OSTypes.ServerActive ]
      , confirmable = False
      }
    , { name = "Resume"
      , description = "Resume suspended server"
      , allowedStatuses = Just [ OSTypes.ServerSuspended ]
      , allowedLockStatus = Just OSTypes.ServerUnlocked
      , action =
            CmdAction <|
                doAction <|
                    Json.Encode.object [ ( "resume", Json.Encode.null ) ]
      , selectMods = [ Modifier.Primary ]
      , targetStatus = Just [ OSTypes.ServerActive ]
      , confirmable = False
      }
    , { name = "Unshelve"
      , description = "Restore shelved server"
      , allowedStatuses = Just [ OSTypes.ServerShelved, OSTypes.ServerShelvedOffloaded ]
      , allowedLockStatus = Just OSTypes.ServerUnlocked
      , action =
            CmdAction <|
                doAction (Json.Encode.object [ ( "unshelve", Json.Encode.null ) ])
      , selectMods = [ Modifier.Primary ]
      , targetStatus = Just [ OSTypes.ServerActive ]
      , confirmable = False
      }
    , { name = "Suspend"
      , description = "Save execution state to disk"
      , allowedStatuses = Just [ OSTypes.ServerActive ]
      , allowedLockStatus = Just OSTypes.ServerUnlocked
      , action =
            CmdAction <|
                doAction <|
                    Json.Encode.object [ ( "suspend", Json.Encode.null ) ]
      , selectMods = []
      , targetStatus = Just [ OSTypes.ServerSuspended ]
      , confirmable = False
      }
    , { name = "Shelve"
      , description = "Shut down server and offload it from compute host"
      , allowedStatuses = Just [ OSTypes.ServerActive, OSTypes.ServerShutoff, OSTypes.ServerPaused, OSTypes.ServerSuspended ]
      , allowedLockStatus = Just OSTypes.ServerUnlocked
      , action =
            CmdAction <|
                doAction (Json.Encode.object [ ( "shelve", Json.Encode.null ) ])
      , selectMods = []
      , targetStatus = Just [ OSTypes.ServerShelved, OSTypes.ServerShelvedOffloaded ]
      , confirmable = False
      }
    , { name = "Image"
      , description = "Create snapshot image of server"
      , allowedStatuses = Just [ OSTypes.ServerActive, OSTypes.ServerShutoff, OSTypes.ServerPaused, OSTypes.ServerSuspended ]
      , allowedLockStatus = Nothing
      , action =
            UpdateAction <|
                \projectId server ->
                    ProjectMsg
                        projectId
                        (SetProjectView
                            (CreateServerImage
                                server.osProps.uuid
                                (server.osProps.name ++ "-image")
                            )
                        )
      , selectMods = []
      , targetStatus = Just [ OSTypes.ServerActive ]
      , confirmable = False
      }
    , { name = "Reboot"
      , description = "Restart server"
      , allowedStatuses = Just [ OSTypes.ServerActive, OSTypes.ServerShutoff ]
      , allowedLockStatus = Just OSTypes.ServerUnlocked

      -- TODO soft and hard reboot? Call hard reboot "reset"?
      , action =
            CmdAction <|
                doAction <|
                    Json.Encode.object
                        [ ( "reboot"
                          , Json.Encode.object
                                [ ( "type", Json.Encode.string "SOFT" ) ]
                          )
                        ]
      , selectMods = [ Modifier.Warning ]
      , targetStatus = Just [ OSTypes.ServerActive ]
      , confirmable = False
      }
    , { name = "Delete"
      , description = "Destroy server"
      , allowedStatuses =
            Just
                [ OSTypes.ServerPaused
                , OSTypes.ServerSuspended
                , OSTypes.ServerActive
                , OSTypes.ServerReboot
                , OSTypes.ServerShutoff
                , OSTypes.ServerStopped
                , OSTypes.ServerError
                , OSTypes.ServerBuilding
                , OSTypes.ServerRescued
                , OSTypes.ServerShelved
                , OSTypes.ServerShelvedOffloaded
                ]
      , allowedLockStatus = Just OSTypes.ServerUnlocked
      , action =
            CmdAction <| Rest.Nova.requestDeleteServer
      , selectMods = [ Modifier.Danger ]
      , targetStatus = Just [ OSTypes.ServerSoftDeleted ]
      , confirmable = True
      }

    {-
       -- Not showing to users
       , { name = "Pause"
         , description = "Stop server execution but persist memory state"
         , allowedStatuses = [ OSTypes.ServerActive ]
         , action = doAction <| Json.Encode.object [ ( "pause", Json.Encode.null ) ]
         , selectMods = []
         , targetStatus = [ OSTypes.ServerPaused ]
         }
    -}
    {-
       -- Not showing to users
       , { name = "Stop"
         , description = "Shut down server"
         , allowedStatuses = [ OSTypes.ServerActive ]
         , action = doAction <| Json.Encode.object [ ( "os-stop", Json.Encode.null ) ]
         , selectMods = []
         , targetStatus = [ OSTypes.ServerStopped ]
         }
    -}
    ]


doAction : Json.Encode.Value -> Project -> Server -> Cmd Msg
doAction body project server =
    let
        errorContext =
            ErrorContext
                ("perform action for server " ++ server.osProps.uuid)
                ErrorCrit
                Nothing
    in
    openstackCredentialedRequest
        project
        Post
        Nothing
        (project.endpoints.nova ++ "/servers/" ++ server.osProps.uuid ++ "/action")
        (Http.jsonBody body)
        (Http.expectString
            (resultToMsg errorContext (\_ -> ProjectMsg (Helpers.getProjectId project) <| RequestServer server.osProps.uuid))
        )
