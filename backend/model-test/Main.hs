{-# LANGUAGE OverloadedStrings #-}

-- Model test of the sale and register commands against a running backend.
--
-- It needs a backend with a new database and an admin account. The
-- dev-shell command test-model starts both and then runs this.
--
--   MODEL_TESTS           sequences for the one-puppet test, default 100
--   MODEL_SIZE            most commands in one sequence, default 60
--   MODEL_PUPPETS         puppets running at once, default 4
--   MODEL_PARALLEL_TESTS  rounds of the puppets test, default 30
--
-- The other settings are listed at Model.Exec.setup.
module Main (main) where

import Control.Monad (forM_, unless)
import Data.Maybe (fromMaybe)
import Hedgehog (Group (..), checkSequential)
import System.Environment (lookupEnv)
import System.Exit (exitFailure)
import System.IO (BufferMode (..), hSetBuffering, hSetEncoding, stderr, stdout, utf8)
import Text.Read (readMaybe)

import Model.Exec (Shared (..), setup)
import Model.Observe (closeObservers, lagSummary)
import Model.Parallel (prop_puppetsAgree)
import Model.Property (prop_backendMatchesModel)

envInt :: String -> Int -> IO Int
envInt name fallback = do
  raw <- lookupEnv name
  pure (fromMaybe fallback (raw >>= readMaybe))

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  -- Hedgehog's report uses box-drawing characters.
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  tests   <- envInt "MODEL_TESTS" 100
  size    <- envInt "MODEL_SIZE" 60
  puppets <- envInt "MODEL_PUPPETS" 4
  rounds  <- envInt "MODEL_PARALLEL_TESTS" 30
  shared  <- setup
  passed <-
    checkSequential $
      Group
        "cheeblr model test"
        [ ( "the backend answers every command sequence as the model does"
          , prop_backendMatchesModel shared tests size
          )
        , ( "puppets running at once agree with their models and with each other"
          , prop_puppetsAgree shared rounds puppets size
          )
        ]
  forM_ (sharedObservers shared) $ \observers -> do
    summary <- lagSummary observers
    putStrLn ""
    putStrLn "Event lag, from the command's answer to the event's arrival (negative: the event came first):"
    forM_ summary $ \(stream, count, median, worst) ->
      putStrLn ("  " <> show stream <> ": " <> show count <> " events, median " <> ms median <> ", worst " <> ms worst)
    closeObservers observers
  unless passed exitFailure
  where
    ms x = show (round x :: Int) <> " ms"