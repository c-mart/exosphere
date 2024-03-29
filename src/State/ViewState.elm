module State.ViewState exposing
    ( defaultViewState
    , modelUpdateViewState
    , setNonProjectView
    , setProjectView
    )

import AppUrl.Builder
import Browser.Navigation
import Helpers.GetterSetters as GetterSetters
import Helpers.Helpers as Helpers
import Helpers.Random as RandomHelpers
import OpenStack.Quotas as OSQuotas
import OpenStack.Types as OSTypes
import OpenStack.Volumes as OSVolumes
import Ports
import RemoteData
import Rest.ApiModelHelpers as ApiModelHelpers
import Rest.Glance
import Rest.Keystone
import Rest.Nova
import State.Error
import Style.Widgets.NumericTextInput.NumericTextInput
import Time
import Types.Defaults as Defaults
import Types.Error as Error
import Types.Types
    exposing
        ( Model
        , Msg(..)
        , NonProjectViewConstructor(..)
        , Project
        , ProjectSpecificMsgConstructor(..)
        , ProjectViewConstructor(..)
        , ServerOrigin(..)
        , UnscopedProvider
        , ViewState(..)
        )
import View.Helpers
import View.PageTitle


setNonProjectView : NonProjectViewConstructor -> Model -> ( Model, Cmd Msg )
setNonProjectView nonProjectViewConstructor model =
    let
        prevNonProjectViewConstructor =
            case model.viewState of
                NonProjectView nonProjectViewConstructor_ ->
                    if nonProjectViewConstructor == nonProjectViewConstructor_ then
                        Nothing

                    else
                        Just nonProjectViewConstructor_

                _ ->
                    Nothing

        ( viewSpecificModel, viewSpecificCmd ) =
            case nonProjectViewConstructor of
                GetSupport _ _ _ ->
                    case prevNonProjectViewConstructor of
                        Just (GetSupport _ _ _) ->
                            ( model, Cmd.none )

                        _ ->
                            ( model, Ports.instantiateClipboardJs () )

                HelpAbout ->
                    case prevNonProjectViewConstructor of
                        Just HelpAbout ->
                            ( model, Cmd.none )

                        _ ->
                            ( model, Ports.instantiateClipboardJs () )

                LoadingUnscopedProjects authTokenStr ->
                    -- This is a smell. We're using view state solely to pass information for an XHR, and we're figuring out here whether we can actually make that XHR. This logic should probably live somewhere else.
                    case model.openIdConnectLoginConfig of
                        Nothing ->
                            let
                                errorContext =
                                    Error.ErrorContext
                                        "Load projects for provider authenticated via OpenID Connect"
                                        Error.ErrorCrit
                                        Nothing
                            in
                            State.Error.processStringError
                                model
                                errorContext
                                "This deployment of Exosphere is not configured to use OpenID Connect."

                        Just openIdConnectLoginConfig ->
                            let
                                oneHourMillis =
                                    1000 * 60 * 60

                                tokenExpiry =
                                    -- One hour later? This should never matter
                                    Time.posixToMillis model.clientCurrentTime
                                        + oneHourMillis
                                        |> Time.millisToPosix

                                unscopedProvider =
                                    UnscopedProvider
                                        openIdConnectLoginConfig.keystoneAuthUrl
                                        (OSTypes.UnscopedAuthToken
                                            tokenExpiry
                                            authTokenStr
                                        )
                                        RemoteData.NotAsked

                                newUnscopedProviders =
                                    unscopedProvider :: model.unscopedProviders

                                newModel =
                                    { model | unscopedProviders = newUnscopedProviders }
                            in
                            ( newModel
                            , Rest.Keystone.requestUnscopedProjects unscopedProvider model.cloudCorsProxyUrl
                            )

                _ ->
                    ( model, Cmd.none )

        newViewState =
            NonProjectView nonProjectViewConstructor
    in
    ( viewSpecificModel, viewSpecificCmd )
        |> Helpers.pipelineCmd (modelUpdateViewState newViewState)


setProjectView : Project -> ProjectViewConstructor -> Model -> ( Model, Cmd Msg )
setProjectView project projectViewConstructor model =
    let
        prevProjectViewConstructor =
            case model.viewState of
                ProjectView projectId _ projectViewConstructor_ ->
                    if projectId == project.auth.project.uuid then
                        Just projectViewConstructor_

                    else
                        Nothing

                _ ->
                    Nothing

        newViewState =
            ProjectView project.auth.project.uuid Defaults.projectViewParams projectViewConstructor

        viewSpecificModelAndCmd =
            case projectViewConstructor of
                AllResources _ ->
                    -- Don't fire cmds if we're already in this view
                    case prevProjectViewConstructor of
                        Just (AllResources _) ->
                            ( model, Cmd.none )

                        _ ->
                            let
                                ( newModel, newCmd ) =
                                    ApiModelHelpers.requestServers project.auth.project.uuid model
                            in
                            ( newModel
                            , Cmd.batch
                                [ newCmd
                                , OSVolumes.requestVolumes project
                                , Rest.Nova.requestKeypairs project
                                , OSQuotas.requestComputeQuota project
                                , OSQuotas.requestVolumeQuota project
                                , Ports.instantiateClipboardJs ()
                                ]
                            )
                                |> Helpers.pipelineCmd
                                    (ApiModelHelpers.requestFloatingIps
                                        project.auth.project.uuid
                                    )

                ListImages _ _ ->
                    let
                        cmd =
                            -- Don't fire cmds if we're already in this view
                            case prevProjectViewConstructor of
                                Just (ListImages _ _) ->
                                    Cmd.none

                                _ ->
                                    Rest.Glance.requestImages model project
                    in
                    ( model, cmd )

                ListProjectServers _ ->
                    -- Don't fire cmds if we're already in this view
                    case prevProjectViewConstructor of
                        Just (ListProjectServers _) ->
                            ( model, Cmd.none )

                        _ ->
                            ApiModelHelpers.requestServers
                                project.auth.project.uuid
                                model
                                |> Helpers.pipelineCmd
                                    (ApiModelHelpers.requestFloatingIps
                                        project.auth.project.uuid
                                    )

                ServerDetail serverUuid _ ->
                    -- Don't fire cmds if we're already in this view
                    case prevProjectViewConstructor of
                        Just (ServerDetail _ _) ->
                            ( model, Cmd.none )

                        _ ->
                            let
                                newModel =
                                    project
                                        |> GetterSetters.modelUpdateProject model

                                cmd =
                                    Cmd.batch
                                        [ Rest.Nova.requestFlavors project
                                        , Rest.Glance.requestImages model project
                                        , OSVolumes.requestVolumes project
                                        , Ports.instantiateClipboardJs ()
                                        ]
                            in
                            ( newModel, cmd )
                                |> Helpers.pipelineCmd
                                    (ApiModelHelpers.requestServer project.auth.project.uuid serverUuid)

                CreateServerImage _ _ ->
                    ( model, Cmd.none )

                CreateServer viewParams ->
                    case model.viewState of
                        -- If we are already in this view state then ensure user isn't trying to choose a server count
                        -- that would exceed quota; if so, reduce server count to comply with quota.
                        ProjectView _ _ (CreateServer _) ->
                            let
                                newViewParams =
                                    case
                                        ( GetterSetters.flavorLookup project viewParams.flavorUuid
                                        , project.computeQuota
                                        , project.volumeQuota
                                        )
                                    of
                                        ( Just flavor, RemoteData.Success computeQuota, RemoteData.Success volumeQuota ) ->
                                            let
                                                availServers =
                                                    OSQuotas.overallQuotaAvailServers
                                                        (viewParams.volSizeTextInput
                                                            |> Maybe.andThen Style.Widgets.NumericTextInput.NumericTextInput.toMaybe
                                                        )
                                                        flavor
                                                        computeQuota
                                                        volumeQuota
                                            in
                                            { viewParams
                                                | count =
                                                    case availServers of
                                                        Just availServers_ ->
                                                            if viewParams.count > availServers_ then
                                                                availServers_

                                                            else
                                                                viewParams.count

                                                        Nothing ->
                                                            viewParams.count
                                            }

                                        ( _, _, _ ) ->
                                            viewParams

                                newModel =
                                    { model
                                        | viewState =
                                            ProjectView
                                                project.auth.project.uuid
                                                { createPopup = False }
                                            <|
                                                CreateServer newViewParams
                                    }
                            in
                            ( newModel
                            , Cmd.none
                            )

                        -- If we are just entering this view then gather everything we need
                        _ ->
                            let
                                newViewParamsMsg serverName_ =
                                    ProjectMsg project.auth.project.uuid <|
                                        SetProjectView <|
                                            CreateServer { viewParams | serverName = serverName_ }

                                cmd =
                                    Cmd.batch
                                        [ Rest.Nova.requestFlavors project
                                        , Rest.Nova.requestKeypairs project
                                        , RandomHelpers.generateServerName newViewParamsMsg
                                        ]
                            in
                            ( model, cmd )
                                |> Helpers.pipelineCmd (ApiModelHelpers.requestAutoAllocatedNetwork project.auth.project.uuid)
                                |> Helpers.pipelineCmd (ApiModelHelpers.requestComputeQuota project.auth.project.uuid)
                                |> Helpers.pipelineCmd (ApiModelHelpers.requestVolumeQuota project.auth.project.uuid)

                ListProjectVolumes _ ->
                    let
                        cmd =
                            -- Don't fire cmds if we're already in this view
                            case prevProjectViewConstructor of
                                Just (ListProjectVolumes _) ->
                                    Cmd.none

                                _ ->
                                    Cmd.batch
                                        [ OSVolumes.requestVolumes project
                                        , Ports.instantiateClipboardJs ()
                                        ]
                    in
                    ( model, cmd )

                ListFloatingIps _ ->
                    case prevProjectViewConstructor of
                        Just (ListFloatingIps _) ->
                            ( model, Cmd.none )

                        _ ->
                            ( model, Ports.instantiateClipboardJs () )
                                |> Helpers.pipelineCmd
                                    (ApiModelHelpers.requestFloatingIps project.auth.project.uuid)
                                |> Helpers.pipelineCmd
                                    (ApiModelHelpers.requestComputeQuota project.auth.project.uuid)
                                |> Helpers.pipelineCmd
                                    (ApiModelHelpers.requestServers project.auth.project.uuid)

                AssignFloatingIp _ ->
                    case prevProjectViewConstructor of
                        Just (AssignFloatingIp _) ->
                            ( model, Cmd.none )

                        _ ->
                            ( model, Cmd.none )
                                |> Helpers.pipelineCmd
                                    (ApiModelHelpers.requestFloatingIps project.auth.project.uuid)
                                |> Helpers.pipelineCmd (ApiModelHelpers.requestPorts project.auth.project.uuid)

                ListKeypairs _ ->
                    let
                        cmd =
                            -- Don't fire cmds if we're already in this view
                            case prevProjectViewConstructor of
                                Just (ListKeypairs _) ->
                                    Cmd.none

                                _ ->
                                    Cmd.batch
                                        [ Rest.Nova.requestKeypairs project
                                        , Ports.instantiateClipboardJs ()
                                        ]
                    in
                    ( model, cmd )

                CreateKeypair _ _ ->
                    ( model, Cmd.none )

                VolumeDetail _ _ ->
                    ( model, Cmd.none )

                AttachVolumeModal _ _ ->
                    case prevProjectViewConstructor of
                        Just (AttachVolumeModal _ _) ->
                            ( model, Cmd.none )

                        _ ->
                            let
                                cmd =
                                    OSVolumes.requestVolumes project
                            in
                            ( model, cmd )
                                |> Helpers.pipelineCmd (ApiModelHelpers.requestServers project.auth.project.uuid)

                MountVolInstructions _ ->
                    ( model, Cmd.none )

                CreateVolume _ _ ->
                    let
                        cmd =
                            -- If just entering this view, get volume quota
                            case model.viewState of
                                ProjectView _ _ (CreateVolume _ _) ->
                                    Cmd.none

                                _ ->
                                    OSQuotas.requestVolumeQuota project
                    in
                    ( model, cmd )
    in
    viewSpecificModelAndCmd
        |> Helpers.pipelineCmd (modelUpdateViewState newViewState)


modelUpdateViewState : ViewState -> Model -> ( Model, Cmd Msg )
modelUpdateViewState viewState model =
    -- the cmd argument is just a "passthrough", added to the Cmd that sets new URL
    let
        urlWithoutQuery url =
            String.split "?" url
                |> List.head
                |> Maybe.withDefault ""

        prevUrl =
            model.prevUrl

        newUrl =
            AppUrl.Builder.viewStateToUrl model.urlPathPrefix viewState

        newModel =
            { model
                | viewState = viewState
                , prevUrl = newUrl
            }

        newViewContext =
            View.Helpers.toViewContext newModel

        newPageTitle =
            View.PageTitle.pageTitle newModel newViewContext

        ( updateUrlFunc, updateMatomoCmd ) =
            if urlWithoutQuery newUrl == urlWithoutQuery prevUrl then
                -- We should `replaceUrl` and not update Matomo when just modifying the query string (setting parameters of views)
                ( Browser.Navigation.replaceUrl, Cmd.none )

            else
                -- We should `pushUrl` and update Matomo when modifying the path (moving between views)
                ( Browser.Navigation.pushUrl, Ports.pushUrlAndTitleToMatomo { newUrl = newUrl, pageTitle = newPageTitle } )

        urlCmd =
            Cmd.batch
                [ updateUrlFunc model.navigationKey newUrl
                , updateMatomoCmd
                ]
    in
    ( newModel, urlCmd )


defaultViewState : Model -> ViewState
defaultViewState model =
    let
        defaultLoginViewState =
            model.style.defaultLoginView
                |> Maybe.map (\loginView -> NonProjectView (Login loginView))
                |> Maybe.withDefault (NonProjectView LoginPicker)
    in
    case model.projects of
        [] ->
            defaultLoginViewState

        firstProject :: _ ->
            ProjectView
                firstProject.auth.project.uuid
                Defaults.projectViewParams
                (AllResources
                    Defaults.allResourcesListViewParams
                )
