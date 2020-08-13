module View.AttachVolume exposing (attachVolume, mountVolInstructions)

import Element
import Element.Font as Font
import Element.Input as Input
import Framework.Button as Button
import Framework.Modifier as Modifier
import Helpers.Helpers as Helpers
import Helpers.RemoteDataPlusPlus as RDPP
import OpenStack.Types as OSTypes
import RemoteData
import Types.Types
    exposing
        ( IPInfoLevel(..)
        , Msg(..)
        , PasswordVisibility(..)
        , Project
        , ProjectSpecificMsgConstructor(..)
        , ProjectViewConstructor(..)
        )
import View.Helpers as VH


attachVolume : Project -> Maybe OSTypes.ServerUuid -> Maybe OSTypes.VolumeUuid -> Element.Element Msg
attachVolume project maybeServerUuid maybeVolumeUuid =
    let
        serverChoices =
            -- Future TODO instead of hiding servers that are ineligible to have a newly attached volume, show them grayed out with mouseover text like "volume cannot be attached to this server because X"
            RDPP.withDefault [] project.servers
                |> List.filter
                    (\s ->
                        not <|
                            List.member
                                s.osProps.details.openstackStatus
                                [ OSTypes.ServerShelved
                                , OSTypes.ServerShelvedOffloaded
                                , OSTypes.ServerError
                                , OSTypes.ServerSoftDeleted
                                , OSTypes.ServerBuilding
                                ]
                    )
                |> List.map
                    (\s ->
                        Input.option s.osProps.uuid
                            (Element.text <| VH.possiblyUntitledResource s.osProps.name "server")
                    )

        volumeChoices =
            RemoteData.withDefault [] project.volumes
                |> List.filter (\v -> v.status == OSTypes.Available)
                |> List.map
                    (\v ->
                        Input.option
                            v.uuid
                            (Element.row VH.exoRowAttributes
                                [ Element.text <| VH.possiblyUntitledResource v.name "volume"
                                , Element.text " - "
                                , Element.text <| String.fromInt v.size ++ " GB"
                                ]
                            )
                    )
    in
    Element.column VH.exoColumnAttributes
        [ Element.el VH.heading2 <| Element.text "Attach a Volume"
        , Input.radio []
            { label = Input.labelAbove [ Element.paddingXY 0 12 ] (Element.text "Select a server")
            , onChange = \new -> ProjectMsg (Helpers.getProjectId project) (SetProjectView (AttachVolumeModal (Just new) maybeVolumeUuid))
            , options = serverChoices
            , selected = maybeServerUuid
            }
        , Input.radio []
            -- TODO if no volumes in list, suggest user create a volume and provide link to that view
            { label = Input.labelAbove [ Element.paddingXY 0 12 ] (Element.text "Select a volume")
            , onChange = \new -> ProjectMsg (Helpers.getProjectId project) (SetProjectView (AttachVolumeModal maybeServerUuid (Just new)))
            , options = volumeChoices
            , selected = maybeVolumeUuid
            }
        , let
            params =
                case ( maybeServerUuid, maybeVolumeUuid ) of
                    ( Just serverUuid, Just volumeUuid ) ->
                        let
                            volAttachedToServer =
                                Helpers.serverLookup project serverUuid
                                    |> Maybe.map (Helpers.volumeIsAttachedToServer volumeUuid)
                                    |> Maybe.withDefault False
                        in
                        if volAttachedToServer then
                            { attribs = [ Modifier.Disabled ]
                            , onPress = Nothing
                            , warnText = Just "This volume is already attached to this server."
                            }

                        else
                            { attribs = [ Modifier.Primary ]
                            , onPress = Just <| ProjectMsg (Helpers.getProjectId project) (RequestAttachVolume serverUuid volumeUuid)
                            , warnText = Nothing
                            }

                    _ ->
                        {- User hasn't selected a server and volume yet so we keep the button disabled but don't yell at him/her -}
                        { attribs = [ Modifier.Disabled ]
                        , onPress = Nothing
                        , warnText = Nothing
                        }

            button =
                Element.el [ Element.alignRight ] <|
                    Button.button
                        params.attribs
                        params.onPress
                        "Attach"
          in
          Element.row [ Element.width Element.fill ]
            [ case params.warnText of
                Just warnText ->
                    Element.el [ Font.color <| Element.rgb255 255 56 96 ] <| Element.text warnText

                Nothing ->
                    Element.none
            , button
            ]
        ]


mountVolInstructions : Project -> OSTypes.VolumeAttachment -> Element.Element Msg
mountVolInstructions project attachment =
    Element.column VH.exoColumnAttributes
        [ Element.el VH.heading2 <| Element.text "Volume Attached"
        , Element.text ("Device: " ++ attachment.device)
        , case Helpers.volDeviceToMountpoint attachment.device of
            Just mountpoint ->
                Element.text ("Mount point: " ++ mountpoint)

            Nothing ->
                Element.none
        , Element.paragraph []
            [ case Helpers.volDeviceToMountpoint attachment.device of
                Just mountpoint ->
                    Element.text <|
                        "We'll try to mount this volume at "
                            ++ mountpoint
                            ++ " on your instance's filesystem. You should be able to access the volume there. "
                            ++ "If it's a completely empty volume we'll also try to format it first. "
                            ++ "This may not work on older operating systems (like CentOS 7 or Ubuntu 16.04). "
                            ++ "In that case, you may need to format and/or mount the volume manually."

                Nothing ->
                    Element.text <|
                        "We attached the volume but couldn't determine a mountpoint from the device path. You "
                            ++ "may need to format and/or mount the volume manually."
            ]
        , Button.button
            []
            (Just <|
                ProjectMsg
                    (Helpers.getProjectId project)
                <|
                    SetProjectView
                        (ServerDetail
                            attachment.serverUuid
                            { verboseStatus = False
                            , passwordVisibility = PasswordHidden
                            , ipInfoLevel = IPSummary
                            , serverActionNamePendingConfirmation = Nothing
                            }
                        )
            )
            "Go to my server"
        ]
