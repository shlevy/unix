{-# OPTIONS -fffi #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  System.Posix.Process
-- Copyright   :  (c) The University of Glasgow 2002
-- License     :  BSD-style (see the file libraries/base/LICENSE)
-- 
-- Maintainer  :  libraries@haskell.org
-- Stability   :  provisional
-- Portability :  non-portable (requires POSIX)
--
-- POSIX process support
--
-----------------------------------------------------------------------------

module System.Posix.Process (
    -- * Processes

    -- ** Forking and executing
    forkProcess, executeFile,
    
    -- ** Exiting
    exitImmediately,

    -- ** Process environment
    getProcessID,
    getParentProcessID,
    getProcessGroupID,

    -- ** Process groups
    createProcessGroup,
    joinProcessGroup,
    setProcessGroupID,

    -- ** Sessions
    createSession,

    -- ** Process times
    ProcessTimes(elapsedTime, systemTime, userTime,
		 childSystemTime, childUserTime),
    getProcessTimes,

    -- ** Scheduling priority
    nice,
    getProcessPriority,
    getProcessGroupPriority,
    getUserPriority,
    setProcessPriority,
    setProcessGroupPriority,
    setUserPriority,

    -- ** Process status
    ProcessStatus(..),
    getProcessStatus,
    getAnyProcessStatus,
    getGroupProcessStatus,

-- ToDo:
--    getEnvVar,
--    getEnvironment,
 ) where

#include "HsUnix.h"
#include <sys/times.h>

import Foreign
import Foreign.C
import System.IO
import System.IO.Error
import System.Exit
import System.Posix.Types
import System.Posix.Signals

-- -----------------------------------------------------------------------------
-- Process environment

getProcessID :: IO ProcessID
getProcessID = c_getpid

foreign import ccall unsafe "getpid"
   c_getpid :: IO CPid

getParentProcessID :: IO ProcessID
getParentProcessID = c_getppid

foreign import ccall unsafe "getppid"
  c_getppid :: IO CPid

getProcessGroupID :: IO ProcessGroupID
getProcessGroupID = c_getpgrp

foreign import ccall unsafe "getpgrp"
  c_getpgrp :: IO CPid

createProcessGroup :: ProcessID -> IO ProcessGroupID
createProcessGroup pid = do
  throwErrnoIfMinus1_ "createProcessGroup" (c_setpgid pid 0)
  return pid

joinProcessGroup :: ProcessGroupID -> IO ()
joinProcessGroup pgid =
  throwErrnoIfMinus1_ "joinProcessGroup" (c_setpgid 0 pgid)

setProcessGroupID :: ProcessID -> ProcessGroupID -> IO ()
setProcessGroupID pid pgid =
  throwErrnoIfMinus1_ "setProcessGroupID" (c_setpgid pid pgid)

foreign import ccall unsafe "setpgid"
  c_setpgid :: CPid -> CPid -> IO CInt

createSession :: IO ProcessGroupID
createSession = throwErrnoIfMinus1 "createSession" c_setsid

foreign import ccall unsafe "setsid"
  c_setsid :: IO CPid

-- -----------------------------------------------------------------------------
-- Process times

-- All times in clock ticks (see getClockTick)

data ProcessTimes
  = ProcessTimes { elapsedTime     :: ClockTick
  		 , userTime        :: ClockTick
		 , systemTime      :: ClockTick
		 , childUserTime   :: ClockTick
		 , childSystemTime :: ClockTick
		 }

getProcessTimes :: IO ProcessTimes
getProcessTimes = do
   allocaBytes (#const sizeof(struct tms)) $ \p_tms -> do
     elapsed <- throwErrnoIfMinus1 "getProcessTimes" (c_times p_tms)
     ut  <- (#peek struct tms, tms_utime)  p_tms
     st  <- (#peek struct tms, tms_stime)  p_tms
     cut <- (#peek struct tms, tms_cutime) p_tms
     cst <- (#peek struct tms, tms_cstime) p_tms
     return (ProcessTimes{ elapsedTime     = elapsed,
	 		   userTime        = ut,
	 		   systemTime      = st,
	 		   childUserTime   = cut,
	 		   childSystemTime = cst
			  })

type CTms = ()

foreign import ccall unsafe "times"
  c_times :: Ptr CTms -> IO CClock

-- -----------------------------------------------------------------------------
-- Process scheduling priority

nice :: Int -> IO ()
nice prio = throwErrnoIfMinus1_ "nice" (c_nice (fromIntegral prio))

foreign import ccall unsafe "nice"
  c_nice :: CInt -> IO CInt

getProcessPriority      :: ProcessID      -> IO Int
getProcessGroupPriority :: ProcessGroupID -> IO Int
getUserPriority         :: UserID         -> IO Int

getProcessPriority pid = do
  r <- throwErrnoIfMinus1 "getProcessPriority" $
         c_getpriority (#const PRIO_PROCESS) (fromIntegral pid)
  return (fromIntegral r)

getProcessGroupPriority pid = do
  r <- throwErrnoIfMinus1 "getProcessPriority" $
         c_getpriority (#const PRIO_PGRP) (fromIntegral pid)
  return (fromIntegral r)

getUserPriority uid = do
  r <- throwErrnoIfMinus1 "getUserPriority" $
         c_getpriority (#const PRIO_USER) (fromIntegral uid)
  return (fromIntegral r)

foreign import ccall unsafe "getpriority"
  c_getpriority :: CInt -> CInt -> IO CInt

setProcessPriority      :: ProcessID      -> Int -> IO ()
setProcessGroupPriority :: ProcessGroupID -> Int -> IO ()
setUserPriority         :: UserID         -> Int -> IO ()

setProcessPriority pid val = 
  throwErrnoIfMinus1_ "setProcessPriority" $
    c_setpriority (#const PRIO_PROCESS) (fromIntegral pid) (fromIntegral val)

setProcessGroupPriority pid val =
  throwErrnoIfMinus1_ "setProcessPriority" $
    c_setpriority (#const PRIO_PGRP) (fromIntegral pid) (fromIntegral val)

setUserPriority uid val =
  throwErrnoIfMinus1_ "setUserPriority" $
    c_setpriority (#const PRIO_USER) (fromIntegral uid) (fromIntegral val)

foreign import ccall unsafe "setpriority"
  c_setpriority :: CInt -> CInt -> CInt -> IO CInt

-- -----------------------------------------------------------------------------
-- Forking, execution

forkProcess :: IO (Maybe ProcessID)
forkProcess = do
  r <- throwErrnoIfMinus1 "forkProcess" c_fork
  case r of
     0   -> return Nothing
     pid -> return (Just (fromIntegral pid))

foreign import ccall unsafe "fork"
  c_fork :: IO CInt


executeFile :: FilePath			    -- Command
            -> Bool			    -- Search PATH?
            -> [String]			    -- Arguments
            -> Maybe [(String, String)]	    -- Environment
            -> IO ()
executeFile path search args Nothing = do
  withCString path $ \s ->
    withMany withCString args $ \cstrs ->
      withArray0 nullPtr cstrs $ \arr ->
	if search then
	  throwErrnoIfMinus1_ "executeFile" (c_execvp s arr)
	else
	  throwErrnoIfMinus1_ "executeFile" (c_execv s arr)

executeFile path search args (Just env) = do
  withCString path $ \s ->
    withMany withCString args $ \cstrs ->
      withArray0 nullPtr cstrs $ \arg_arr ->
    let env' = map (\ (name, val) -> name ++ ('=' : val)) env in
    withMany withCString env' $ \cenv ->
      withArray0 nullPtr cenv $ \env_arr ->
	if search then
	  throwErrnoIfMinus1_ "executeFile" (c_execvpe s arg_arr env_arr)
	else
	  throwErrnoIfMinus1_ "executeFile" (c_execve s arg_arr env_arr)

foreign import ccall unsafe "execvp"
  c_execvp :: CString -> Ptr CString -> IO CInt

foreign import ccall unsafe "execv"
  c_execv :: CString -> Ptr CString -> IO CInt

foreign import ccall unsafe "execvpe"
  c_execvpe :: CString -> Ptr CString -> Ptr CString -> IO CInt

foreign import ccall unsafe "execve"
  c_execve :: CString -> Ptr CString -> Ptr CString -> IO CInt

-- -----------------------------------------------------------------------------
-- Waiting for process termination

data ProcessStatus = Exited ExitCode
                   | Terminated Signal
                   | Stopped Signal
		   deriving (Eq, Ord, Show)

getProcessStatus :: Bool -> Bool -> ProcessID -> IO (Maybe ProcessStatus)
getProcessStatus block stopped pid =
  alloca $ \wstatp -> do
    pid <- throwErrnoIfMinus1 "getProcessStatus"
		(c_waitpid pid wstatp (waitOptions block stopped))
    case pid of
      0  -> return Nothing
      _  -> do ps <- decipherWaitStatus wstatp
	       return (Just ps)

foreign import ccall unsafe "waitpid"
  c_waitpid :: CPid -> Ptr CInt -> CInt -> IO CPid

getGroupProcessStatus :: Bool
                      -> Bool
                      -> ProcessGroupID
                      -> IO (Maybe (ProcessID, ProcessStatus))
getGroupProcessStatus block stopped pgid =
  alloca $ \wstatp -> do
    pid <- throwErrnoIfMinus1 "getGroupProcessStatus"
		(c_waitpid (-pgid) wstatp (waitOptions block stopped))
    case pid of
      0  -> return Nothing
      _  -> do ps <- decipherWaitStatus wstatp
	       return (Just (pid, ps))

getAnyProcessStatus :: Bool -> Bool -> IO (Maybe (ProcessID, ProcessStatus))
getAnyProcessStatus block stopped = getGroupProcessStatus block stopped 1

waitOptions :: Bool -> Bool -> CInt
--             block   stopped
waitOptions False False = (#const WNOHANG)
waitOptions False True  = (#const (WNOHANG|WUNTRACED))
waitOptions True  False = 0
waitOptions True  True  = (#const WUNTRACED)

-- Turn a (ptr to a) wait status into a ProcessStatus

decipherWaitStatus :: Ptr CInt -> IO ProcessStatus
decipherWaitStatus wstatp = do
  wstat <- peek wstatp
  if c_WIFEXITED wstat /= 0
      then do
        let exitstatus = c_WEXITSTATUS wstat
        if exitstatus == 0
	   then return (Exited ExitSuccess)
	   else return (Exited (ExitFailure (fromIntegral exitstatus)))
      else do
        if c_WIFSIGNALED wstat /= 0
	   then do
		let termsig = c_WTERMSIG wstat
		return (Terminated (fromIntegral termsig))
	   else do
		if c_WIFSTOPPED wstat /= 0
		   then do
			let stopsig = c_WSTOPSIG wstat
			return (Stopped (fromIntegral stopsig))
		   else do
			ioError (mkIOError illegalOperationErrorType
				   "waitStatus" Nothing Nothing)

foreign import ccall unsafe "__hsunix_wifexited"
  c_WIFEXITED :: CInt -> CInt 

foreign import ccall unsafe "__hsunix_wexitstatus"
  c_WEXITSTATUS :: CInt -> CInt

foreign import ccall unsafe "__hsunix_wifsignaled"
  c_WIFSIGNALED :: CInt -> CInt

foreign import ccall unsafe "__hsunix_wtermsig"
  c_WTERMSIG :: CInt -> CInt 

foreign import ccall unsafe "__hsunix_wifstopped"
  c_WIFSTOPPED :: CInt -> CInt

foreign import ccall unsafe "__hsunix_wstopsig"
  c_WSTOPSIG :: CInt -> CInt

-- -----------------------------------------------------------------------------
-- Exiting

exitImmediately :: ExitCode -> IO ()
exitImmediately exitcode = c_exit (exitcode2Int exitcode)
  where
    exitcode2Int ExitSuccess = 0
    exitcode2Int (ExitFailure n) = fromIntegral n

foreign import ccall unsafe "exit"
  c_exit :: CInt -> IO ()

-- -----------------------------------------------------------------------------
