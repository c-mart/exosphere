module View.QuotaUsage exposing (dashboard)

import Element
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Helpers.String
import OpenStack.Types as OSTypes
import RemoteData exposing (RemoteData(..), WebData)
import Style.Helpers as SH
import Types.Types
    exposing
        ( Msg(..)
        , Project
        )
import View.Helpers as VH
import View.Types


dashboard : View.Types.Context -> Project -> Element.Element Msg
dashboard context project =
    Element.column
        (VH.exoColumnAttributes ++ [ Element.width Element.fill ])
        [ Element.el VH.heading2 <|
            Element.text <|
                String.join " "
                    [ context.localization.maxResourcesPerProject |> Helpers.String.stringToTitleCase
                    , "Usage"
                    ]
        , quotaSections context project
        ]


quotaSections : View.Types.Context -> Project -> Element.Element Msg
quotaSections context project =
    Element.column
        (VH.exoColumnAttributes ++ [ Element.width Element.fill ])
        [ computeQuota context project
        , volumeQuota context project

        -- networkQuota stuff - whenever I find that
        ]


infoItem : View.Types.Context -> { inUse : Int, limit : Maybe Int } -> ( String, String ) -> Element.Element Msg
infoItem context detail ( label, units ) =
    let
        labelLimit m_ =
            m_
                |> Maybe.map labelUse
                |> Maybe.withDefault "N/A"

        labelUse i_ =
            String.fromInt i_

        bg =
            Background.color <| SH.toElementColor context.palette.surface

        border =
            Border.rounded 5

        pad =
            Element.paddingXY 4 2
    in
    Element.row
        (VH.exoRowAttributes ++ [ Element.width Element.fill ])
        [ Element.el [ Font.bold ] <|
            Element.text label
        , Element.el [ bg, border, pad ] <|
            Element.text (labelUse detail.inUse)
        , Element.el [] <|
            Element.text "of"
        , Element.el [ bg, border, pad ] <|
            Element.text (labelLimit detail.limit)
        , Element.el [ Font.italic ] <|
            Element.text units
        ]


computeQuota : View.Types.Context -> Project -> Element.Element Msg
computeQuota context project =
    Element.column
        (VH.exoColumnAttributes ++ [ Element.width Element.fill ])
        [ Element.el VH.heading3 <| Element.text "Compute"
        , computeQuotaDetails context project.computeQuota
        ]


computeInfoItems : View.Types.Context -> OSTypes.ComputeQuota -> Element.Element Msg
computeInfoItems context quota =
    Element.column
        (VH.exoColumnAttributes ++ [ Element.width Element.fill ])
        [ infoItem context quota.cores ( "Cores:", "total" )
        , infoItem context quota.instances ( "Instances:", "total" )
        , infoItem context quota.ram ( "RAM:", "MB" )
        ]


quotaDetail : View.Types.Context -> WebData q -> (q -> Element.Element Msg) -> Element.Element Msg
quotaDetail context quota infoItemsF =
    let
        strProto =
            String.join " "
                [ context.localization.maxResourcesPerProject
                    |> Helpers.String.stringToTitleCase
                , "data"
                ]
    in
    case quota of
        NotAsked ->
            Element.el [] <| Element.text (strProto ++ " loading ...")

        Loading ->
            Element.el [] <| Element.text (strProto ++ " still loading ...")

        Failure _ ->
            Element.el [] <| Element.text (strProto ++ " could not be loaded ...")

        Success quota_ ->
            infoItemsF quota_


computeQuotaDetails : View.Types.Context -> WebData OSTypes.ComputeQuota -> Element.Element Msg
computeQuotaDetails context quota =
    Element.row
        (VH.exoRowAttributes ++ [ Element.width Element.fill ])
        [ quotaDetail context quota (computeInfoItems context) ]


volumeQuota : View.Types.Context -> Project -> Element.Element Msg
volumeQuota context project =
    Element.column
        (VH.exoColumnAttributes ++ [ Element.width Element.fill ])
        [ Element.el VH.heading3 <|
            Element.text
                (context.localization.blockDevice
                    |> Helpers.String.pluralizeWord
                    |> Helpers.String.stringToTitleCase
                )
        , volumeQuoteDetails context project.volumeQuota
        ]


volumeInfoItems : View.Types.Context -> OSTypes.VolumeQuota -> Element.Element Msg
volumeInfoItems context quota =
    Element.column
        (VH.exoColumnAttributes ++ [ Element.width Element.fill ])
        [ infoItem context quota.gigabytes ( "Storage:", "GB" )
        , infoItem
            context
            quota.volumes
            ( String.concat
                [ context.localization.blockDevice
                    |> Helpers.String.pluralizeWord
                    |> Helpers.String.stringToTitleCase
                , ":"
                ]
            , "total"
            )
        ]


volumeQuoteDetails : View.Types.Context -> WebData OSTypes.VolumeQuota -> Element.Element Msg
volumeQuoteDetails context quota =
    Element.row
        (VH.exoRowAttributes ++ [ Element.width Element.fill ])
        [ quotaDetail context quota (volumeInfoItems context) ]
