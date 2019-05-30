module View.Project exposing (project)

import Element
import Framework.Button as Button
import Framework.Modifier as Modifier
import Helpers.Helpers as Helpers
import Maybe
import OpenStack.Types as OSTypes
import Types.Types exposing (..)
import View.AttachVolume
import View.CreateServer
import View.Helpers as VH
import View.Images
import View.Servers
import View.Volumes


project : Model -> Project -> ProjectViewConstructor -> Element.Element Msg
project model p viewConstructor =
    let
        v =
            case viewConstructor of
                ListImages ->
                    View.Images.imagesIfLoaded model.globalDefaults p model.imageFilterTag

                ListProjectServers ->
                    View.Servers.servers p

                ServerDetail serverUuid viewStateParams ->
                    View.Servers.serverDetail p serverUuid viewStateParams

                CreateServer createServerRequest ->
                    View.CreateServer.createServer p createServerRequest

                ListProjectVolumes ->
                    View.Volumes.volumes p

                VolumeDetail volumeUuid ->
                    View.Volumes.volumeDetailView p volumeUuid

                CreateVolume volName volSizeStr ->
                    View.Volumes.createVolume p volName volSizeStr

                AttachVolumeModal maybeServerUuid maybeVolumeUuid ->
                    View.AttachVolume.attachVolume p maybeServerUuid maybeVolumeUuid

                MountVolInstructions attachment ->
                    View.AttachVolume.mountVolInstructions p attachment
    in
    Element.column
        (Element.width Element.fill
            :: VH.exoColumnAttributes
        )
        [ projectNav p
        , v
        ]


projectNav : Project -> Element.Element Msg
projectNav p =
    Element.column [ Element.width Element.fill, Element.spacing 10 ]
        [ Element.el
            VH.heading2
          <|
            Element.text <|
                Helpers.hostnameFromUrl p.creds.authUrl
                    ++ " - "
                    ++ p.creds.projectName

        {- TODO nest these somehow, perhaps put the "create server" and "create volume" buttons as a dropdown under a big "Create" button -}
        , Element.row [ Element.width Element.fill, Element.spacing 10 ]
            [ Element.el
                []
                (Button.button
                    []
                    (Just <|
                        ProjectMsg (Helpers.getProjectId p) <|
                            SetProjectView ListProjectServers
                    )
                    "My Servers"
                )
            , Element.el []
                (Button.button
                    []
                    (Just <| ProjectMsg (Helpers.getProjectId p) <| SetProjectView ListImages)
                    "Create Server"
                )
            , Element.el []
                (Button.button
                    []
                    (Just <| ProjectMsg (Helpers.getProjectId p) <| SetProjectView ListProjectVolumes)
                    "My Volumes"
                )
            , Element.el []
                {- TODO store default values of CreateVolumeRequest (name and size) somewhere else, like global defaults imported by State.elm -}
                (Button.button
                    []
                    (Just <| ProjectMsg (Helpers.getProjectId p) <| SetProjectView <| CreateVolume "" "10")
                    "Create Volume"
                )
            , Element.el
                [ Element.alignRight ]
                (Button.button [ Modifier.Muted ] (Just <| ProjectMsg (Helpers.getProjectId p) RemoveProject) "Remove Project")
            ]
        ]