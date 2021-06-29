{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Cardano.Logging.Tracer.EKG (
  ekgTracer
) where

import           Cardano.Logging.DocuGenerator
import           Cardano.Logging.Types

import           Control.Monad.IO.Class (MonadIO, liftIO)
import qualified Control.Tracer as T
import           Data.IORef (newIORef, readIORef, writeIORef)
import qualified Data.Map.Strict as Map
import           Data.Text (intercalate, pack)
import qualified System.Metrics as Metrics
import qualified System.Metrics.Gauge as Gauge
import qualified System.Metrics.Label as Label
import           System.Remote.Monitoring (Server, getGauge, getLabel)


ekgTracer :: MonadIO m => Either Metrics.Store Server-> m (Trace m FormattedMessage)
ekgTracer storeOrServer = liftIO $ do
    registeredGauges <- newIORef Map.empty
    registeredLabels <- newIORef Map.empty
    pure $ Trace $ T.arrow $ T.emit $ output registeredGauges registeredLabels
  where
    output registeredGauges registeredLabels (LoggingContext{..}, Nothing, FormattedMetrics m) =
      liftIO $ mapM_ (setIt registeredGauges registeredLabels lcNamespace) m
    output _ _ p@(_, Just Document {}, FormattedMetrics m) =
      docIt EKGBackend (FormattedMetrics m) p
    output _ _ (LoggingContext{}, Just _c, _v) =
      pure ()

    setIt registeredGauges _registeredLabels _namespace (IntM ns theInt) = do
      registeredMap <- readIORef registeredGauges
      let name = intercalate "." ns
      case Map.lookup name registeredMap of
        Just gauge -> Gauge.set gauge (fromIntegral theInt)
        Nothing -> do
          gauge <- case storeOrServer of
                      Left store   -> Metrics.createGauge name store
                      Right server -> getGauge name server
          let registeredGauges' = Map.insert name gauge registeredMap
          writeIORef registeredGauges registeredGauges'
          Gauge.set gauge (fromIntegral theInt)
    setIt _registeredGauges registeredLabels _namespace (DoubleM ns theDouble) = do
      registeredMap <- readIORef registeredLabels
      let name = intercalate "." ns
      case Map.lookup name registeredMap of
        Just label -> Label.set label ((pack . show) theDouble)
        Nothing -> do
          label <- case storeOrServer of
                      Left store   -> Metrics.createLabel name store
                      Right server -> getLabel name server
          let registeredLabels' = Map.insert name label registeredMap
          writeIORef registeredLabels registeredLabels'
          Label.set label ((pack . show) theDouble)
