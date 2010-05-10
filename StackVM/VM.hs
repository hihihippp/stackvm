module StackVM.VM (
    VM(..), UpdateFB(..),
    updateThread, getUpdate, newVM, renderPng
) where

import qualified Graphics.GD as GD
import qualified Network.RFB as RFB
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS

import Control.Monad (forever,forM_,join,liftM2)
import Control.Arrow (first,second,(&&&),(***))
import Control.Applicative ((<$>))

import Data.List (find)
import Data.List.Split (splitEvery)
import Data.Word (Word8,Word32)

import Control.Concurrent.MVar
import qualified Data.Map as M

type UpdateID = Int

data VM = VM {
    vmRFB :: RFB.RFB,
    vmMerged :: MVar (M.Map UpdateID UpdateFB),
    vmLatest :: MVar UpdateID
}

data UpdateFB = UpdateFB {
    updateImage :: GD.Image,
    updatePos :: (Int,Int),
    updateSize :: (Int,Int),
    updateID :: UpdateID
}

renderPng :: UpdateFB -> IO BS.ByteString
renderPng UpdateFB{ updateImage = im } = GD.savePngByteString im

newVM :: RFB.RFB -> IO VM
newVM rfb = do
    merged <- newMVar M.empty
    version <- newMVar 0
    
    return $ VM {
        vmRFB = rfb,
        vmMerged = merged,
        vmLatest = version
    }

updateFromImage :: GD.Point -> GD.Size -> GD.Image -> IO UpdateFB
updateFromImage pos size im = do
    return $ UpdateFB {
        updateImage = im,
        updatePos = pos,
        updateSize = size,
        updateID = 1
    }

newUpdate :: RFB.RFB -> [RFB.Rectangle] -> IO UpdateFB
newUpdate rfb rects = do
    let
        -- compute the bounds of the new synthesis image
        n = minimum $ map (snd . RFB.rectPos) rects
        w = minimum $ map (fst . RFB.rectPos) rects
        
        s = maximum ss
        ss = [ (snd $ RFB.rectPos r) + (snd $ RFB.rectSize r) | r <- rects ]
        e = maximum es
        es = [ (fst $ RFB.rectPos r) + (fst $ RFB.rectSize r) | r <- rects ]
        
        size = (e - w, s - n)
    
    im <- GD.newImage size
    forM_ rects $ \rect -> do
        let RFB.Rectangle{ RFB.rectPos = rPos@(rx,ry) } = rect
            RFB.Rectangle{ RFB.rectSize = rSize@(sx,sy) } = rect
            points = liftM2 (,)
                [ rx - w .. rx + sx - w ]
                [ ry - n .. ry + sy - n ]
        case (RFB.rectEncoding rect) of
            RFB.RawEncoding rawData -> do
                srcIm <- RFB.fromByteString rSize rawData
                GD.copyRegion (0,0) rSize srcIm rPos im
            RFB.CopyRectEncoding pos -> do
                screenIm <- RFB.getImage rfb
                GD.copyRegion rPos rSize screenIm pos im
    
    return $ UpdateFB {
        updateImage = im,
        updatePos = (n,w),
        updateSize = size,
        updateID = 1
    }
 
getUpdate :: VM -> UpdateID -> IO UpdateFB
getUpdate vm@VM{ vmMerged = mVar, vmLatest = idVar } uID = do
    vmID <- readMVar idVar
    mergeMap <- takeMVar mVar
    update <- case M.lookup uID mergeMap of
        Just u -> return u
        Nothing -> updateFromImage (0,0) size =<< RFB.getImage (vmRFB vm)
            where
                size = RFB.fbWidth &&& RFB.fbHeight $ rfb
                rfb = RFB.rfbFB (vmRFB vm)
    putMVar mVar
        $ M.insert vmID (update { updateID = vmID })
        $ M.delete uID mergeMap
    return update

-- Overlay the imagery from u1 onto the data and image in u2.
mergeUpdate :: UpdateFB -> UpdateFB -> IO UpdateFB
mergeUpdate u1 u2 = do
    let
        uu = [u1,u2]
        n = minimum $ map (snd . updatePos) uu
        w = minimum $ map (fst . updatePos) uu
        s = maximum [ (snd $ updatePos u) + (snd $ updateSize u) | u <- uu ]
        e = maximum [ (fst $ updatePos u) + (fst $ updateSize u) | u <- uu ]
        
        (width,height) = (e - w, s - n)
        im1 = updateImage u1
        im2 = updateImage u2
        (x,y) = updatePos u1
    
    GD.resizeImage width height im2
    GD.copyRegion (updateSize u1) (0,0) im1 (x - w, y - n) im2
    
    return $ u2 {
        updatePos = (n,w),
        updateSize = (width,height)
    }

updateThread :: VM -> IO ()
updateThread vm@VM{ vmRFB = rfb, vmLatest = idVar } = forever $ do
    let VM{ vmMerged = mVar } = vm
    
    rects <- RFB.rectangles <$> RFB.getUpdate rfb
    
    uID <- (+1) <$> takeMVar idVar
    putMVar idVar uID
    
    print . M.keys =<< readMVar mVar
    
    RFB.renderImages rfb rects
    update <- newUpdate rfb rects
    
    -- merged updates can live around for 20 updates maximum
    putMVar mVar . M.fromList
        =<< mapM (\(k,v) -> ((,) k) <$> mergeUpdate update v)
            . filter ((> (uID - 20)) . fst) . M.toList
        =<< takeMVar mVar
