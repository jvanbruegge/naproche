{- generated by Isabelle -}

{-  Title:      Isabelle/Server.hs
    Author:     Makarius
    LICENSE:    BSD 3-clause (Isabelle)

TCP server on localhost.
-}

{-# LANGUAGE OverloadedStrings #-}

module Isabelle.Server (
  localhost_name, localhost_prefix, localhost, publish_text, publish_stdout,
  server, connection
)
where

import Control.Monad (forever, when)
import qualified Control.Exception as Exception
import Network.Socket (Socket)
import qualified Network.Socket as Socket
import qualified System.IO as IO
import qualified Data.ByteString.Char8 as Char8

import Isabelle.Library
import qualified Isabelle.Bytes as Bytes
import Isabelle.Bytes (Bytes)
import qualified Isabelle.UUID as UUID
import qualified Isabelle.Byte_Message as Byte_Message
import qualified Isabelle.Isabelle_Thread as Isabelle_Thread


{- server address -}

localhost_name :: Bytes
localhost_name = "127.0.0.1"

localhost_prefix :: Bytes
localhost_prefix = localhost_name <> ":"

localhost :: Socket.HostAddress
localhost = Socket.tupleToHostAddress (127, 0, 0, 1)

publish_text :: Bytes -> Bytes -> UUID.T -> Bytes
publish_text name address password =
  "server " <> quote name <> " = " <> address <>
    " (password " <> quote (show_bytes password) <> ")"

publish_stdout :: Bytes -> Bytes -> UUID.T -> IO ()
publish_stdout name address password =
  Char8.putStrLn (Bytes.unmake $ publish_text name address password)


{- server -}

server :: (Bytes -> UUID.T -> IO ()) -> (Socket -> IO ()) -> IO ()
server publish handle =
  Socket.withSocketsDo $ Exception.bracket open (Socket.close . fst) (uncurry loop)
  where
    open :: IO (Socket, Bytes)
    open = do
      server_socket <- Socket.socket Socket.AF_INET Socket.Stream Socket.defaultProtocol
      Socket.bind server_socket (Socket.SockAddrInet 0 localhost)
      Socket.listen server_socket 50

      port <- Socket.socketPort server_socket
      let address = localhost_name <> ":" <> show_bytes port
      password <- UUID.random
      publish address password

      return (server_socket, UUID.print password)

    loop :: Socket -> Bytes -> IO ()
    loop server_socket password = forever $ do
      (connection, _) <- Socket.accept server_socket
      Isabelle_Thread.fork_finally
        (do
          line <- Byte_Message.read_line connection
          when (line == Just password) $ handle connection)
        (\finally -> do
          Socket.close connection
          case finally of
            Left exn -> IO.hPutStrLn IO.stderr $ Exception.displayException exn
            Right () -> return ())
      return ()


{- client connection -}

connection :: String -> Bytes -> (Socket -> IO a) -> IO a
connection port password client =
  Socket.withSocketsDo $ do
    addr <- resolve
    Exception.bracket (open addr) Socket.close body
  where
    resolve = do
      let hints =
            Socket.defaultHints {
              Socket.addrFlags = [Socket.AI_NUMERICHOST, Socket.AI_NUMERICSERV],
              Socket.addrSocketType = Socket.Stream }
      head <$> Socket.getAddrInfo (Just hints) (Just $ make_string localhost_name) (Just port)

    open addr = do
      socket <- Socket.socket (Socket.addrFamily addr) (Socket.addrSocketType addr)
                  (Socket.addrProtocol addr)
      Socket.connect socket $ Socket.addrAddress addr
      return socket

    body socket = do
      Byte_Message.write_line socket password
      client socket
