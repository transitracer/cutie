module Main where

import Network.Simple.TCP.TLS
import qualified Data.ByteString as B
import Data.ByteString.Char8 (pack, unpack)
import System.Environment
import Control.Monad (mapM)
import qualified Cutie.Protocol as IRC
import Cutie.Protocol (msgBuilder)
import Cutie.Commands

-- Usage: cutie "example.irc.network" 6697 cutie_bot

main :: IO ()
main = do (address:port:nick:_) <- getArgs -- gives an awful error, TODO: fix
          -- Only one connection at once, so having the ServiceID suffix be empty is fine
          clientSettings <- getDefaultClientSettings (address, B.empty)
          connect clientSettings address port
            $ \(context, remoteAddr) ->
                do putStrLn $ "Connection established to " ++ show remoteAddr
                   send context $ pack $ "NICK " ++ nick ++ "\r\n"
                   send context $ pack $ "USER " ++ nick ++ " 0 * :Cutie bot!\r\n"
                   sockLoop context

-- I don't like the `IO ()` here, feels quite unclear, but we're doing
-- socket IO. Might be nice to have some bit that would be unwrapped
-- farther up to produce the IO? May be unnecessary though, and we're
-- still logging to console for now, so not quite worth it at the
-- moment honestly
sockLoop :: Context -> IO ()
sockLoop c = do Just dat <- recv c
                putStr $ unpack dat -- log to console
                putStrLn $ show $ IRC.decode dat
                putStrLn $ show $ handle $ IRC.decode dat
                case (handle $ IRC.decode dat) of
                  Just messages -> do
                    mapM_ (putStrLn . unpack . IRC.encode) messages
                    mapM_ (send c . IRC.encode) messages
                  Nothing -> return ()
                sockLoop c

-- Receive a message, and maybe respond, will be moved to another
-- module later down the line.
handle :: Maybe IRC.Message -> Maybe [IRC.Message]
-- This is definitely kinda hard to mentally parse, maybe I should use
-- view patterns here to convert this to a datatype for handleCommand
handle (Just (IRC.Message Nothing _ (IRC.PrivMsg _ ('!':command)))) =
  case (handleCommand $ buildCommand $ command) of
    Just m  -> Just $ map msgBuilder m
    Nothing -> Nothing

-- The reason we have to go through this rigamarole to join, is
-- because Cutiebot is built against an oragono 1.0.0 server, and this
-- is the way to batch `autoreplay-on-join` messages, which are nice
-- for the user, but terrible for a robot like cutiebot. See:
-- https://github.com/oragono/oragono/issues/456#issuecomment-480889973
handle (Just (IRC.Message _ _ (IRC.Identified))) = Just $
  [msgBuilder (IRC.CapabilityRequest [IRC.BatchCapability,
                                     IRC.LabeledResponseCapability])]

handle (Just (IRC.Message _ _ (IRC.CapabilityAck _))) = Just $
  [IRC.Message
   (Just [IRC.LabelTag "joinlabel"])
   Nothing
   (IRC.Join ["#general"] Nothing)]

handle _ = Nothing
  
