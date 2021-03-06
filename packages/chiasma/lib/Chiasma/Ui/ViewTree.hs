module Chiasma.Ui.ViewTree where

import Chiasma.Data.Ident (Ident)
import Chiasma.Lens.Tree (
  LeafIndexTree(..),
  _litTree,
  leafDataTraversal,
  )
import Control.Lens (
  Traversal,
  Traversal',
  anyOf,
  cosmos,
  filtered,
  has,
  ix,
  mapMOf,
  over,
  transformM,
  )
import Control.Monad.Error.Class (throwError)
import Control.Monad.Trans.Writer (WriterT, runWriterT, tell)
import Data.Composition ((.:))

import Chiasma.Ui.Data.TreeModError (TreeModError(PaneMissing, AmbiguousPane, LayoutMissing, AmbiguousLayout))
import Chiasma.Ui.Data.View (
  Pane(Pane),
  PaneView,
  Tree(Tree),
  TreeSub(TreeNode, TreeLeaf),
  View(View),
  ViewTree,
  ViewTreeSub,
  )
import qualified Chiasma.Ui.Data.View as Pane (open)
import qualified Chiasma.Ui.Data.View as TreeSub (leafData)
import qualified Chiasma.Ui.Data.View as View (extra)
import Chiasma.Ui.Data.ViewState (ViewState(ViewState))
import Chiasma.Ui.Pane (paneSetOpen, paneToggleOpen)

modCounted :: Monad m => (a -> m a) -> a -> WriterT (Sum Int) m a
modCounted f a = do
  tell (Sum 1)
  lift $ f a

treeToggleOpen :: ViewTree -> ViewTree
treeToggleOpen (Tree l sub) =
  Tree l (snd $ mapAccumL toggle False sub)
  where
    toggle False (TreeLeaf p) = (True, TreeLeaf (paneToggleOpen p))
    toggle a b = (a, b)

modifyTreeUniqueM :: Monad m => (ViewTree -> m ViewTree) -> Ident -> ViewTree -> ExceptT TreeModError m ViewTree
modifyTreeUniqueM f ident tree = do
  let st = (transformM $ mapMOf (ix ident) (modCounted f)) tree
  (result, Sum count) <- lift $ runWriterT st
  case count of
    1 -> return result
    0 -> throwError $ LayoutMissing ident
    n -> throwError $ AmbiguousLayout ident n

toggleLayout1 :: Ident -> ViewTree -> Either TreeModError ViewTree
toggleLayout1 ident tree =
  runIdentity $ runExceptT $ modifyTreeUniqueM (Identity . treeToggleOpen) ident tree

modifyPaneUniqueM :: Monad m => (PaneView -> m PaneView) -> Ident -> ViewTree -> ExceptT TreeModError m ViewTree
modifyPaneUniqueM f ident tree = do
  let st = (transformM $ mapMOf (ix ident) (modCounted f)) (LeafIndexTree tree)
  (result, Sum count) <- lift $ runWriterT st
  case count of
    1 -> return $ litTree result
    0 -> throwError $ PaneMissing ident
    n -> throwError $ AmbiguousPane ident n

modifyPane :: (PaneView -> PaneView) -> Ident -> ViewTree -> Either TreeModError ViewTree
modifyPane modification ident tree =
  runIdentity $ runExceptT $ modifyPaneUniqueM (Identity . modification) ident tree

openPane :: Ident -> ViewTree -> Either TreeModError ViewTree
openPane =
  modifyPane paneSetOpen

hasOpenPanes :: ViewTree -> Bool
hasOpenPanes tree =
  has (cosmos . _litTree . leafDataTraversal . filtered isOpen) (LeafIndexTree tree)
  where
    isOpen (View _ _ _ (Pane open _ _)) = open

depthTraverseTree ::
  ∀ a.
  Monoid a =>
  (a -> ViewTree -> (a, ViewTree)) ->
  (PaneView -> (a, PaneView)) ->
  ViewTree ->
  (a, ViewTree)
depthTraverseTree transformNode transformLeaf =
  recur
  where
    recur :: ViewTree -> (a, ViewTree)
    recur (Tree l sub) =
      uncurry transformNode . bimap fold (Tree l) . unzip $ (recSub <$> sub)
    recSub :: ViewTreeSub -> (a, ViewTreeSub)
    recSub (TreeNode t) =
      second TreeNode $ recur t
    recSub (TreeLeaf l) =
      second TreeLeaf $ transformLeaf l

data ToggleStatus =
  Minimized
  |
  Opened
  |
  Pristine
  |
  Multiple Int
  |
  Consistent
  deriving (Eq, Show)

instance Semigroup ToggleStatus where
  Pristine <> a = a
  a <> Pristine = a
  Multiple a <> Multiple b = Multiple (a + b)
  Multiple a <> _ = Multiple (a + 1)
  _ <> Multiple a = Multiple (a + 1)
  _ <> _ = Multiple 2

instance Monoid ToggleStatus where
  mempty = Pristine

data ToggleResult a =
  Success a
  |
  NotFound
  |
  Ambiguous Int
  deriving (Eq, Show, Functor)

instance Semigroup (ToggleResult a) where
  NotFound <> a = a
  a <> NotFound = a
  Ambiguous a <> Ambiguous b = Ambiguous (a + b)
  Ambiguous a <> _ = Ambiguous (a + 1)
  _ <> Ambiguous a = Ambiguous (a + 1)
  _ <> _ = Ambiguous 2

instance Monoid (ToggleResult a) where
  mempty = NotFound

instance Applicative ToggleResult where
  pure = Success
  (Success f) <*> fa = fmap f fa
  NotFound <*> _ = NotFound
  Ambiguous n <*> _ = Ambiguous n

instance Monad ToggleResult where
    Success a >>= f = f a
    NotFound >>= _ = NotFound
    Ambiguous n >>= _ = Ambiguous n

openPinnedSubs :: ToggleStatus -> ViewTree -> (ToggleStatus, ViewTree)
openPinnedSubs Pristine t =
  (Pristine, t)
openPinnedSubs Opened (Tree l sub) =
  (Opened, Tree l (openPinnedPane <$> sub))
  where
    openPinnedPane :: ViewTreeSub -> ViewTreeSub
    openPinnedPane (TreeLeaf (View i s g (Pane False True cwd))) =
      TreeLeaf $ View i s g (Pane True True cwd)
    openPinnedPane v =
      v
openPinnedSubs a t =
  (a, t)

checkToggleResult ::
  ToggleStatus ->
  a ->
  ToggleResult a
checkToggleResult =
  checkResult
  where
    checkResult Pristine _ = NotFound
    checkResult (Multiple n) _ = Ambiguous n
    checkResult _ result = Success result

togglePaneView :: Ident -> PaneView -> (ToggleStatus, PaneView)
togglePaneView ident (View i s g (Pane False p c)) | ident == i =
  (Opened, View i s g (Pane True p c))
togglePaneView ident (View i (ViewState minimized) g (Pane True p c)) | ident == i =
  (Minimized, View i (ViewState (not minimized)) g (Pane False p c))
togglePaneView _ v =
  (Pristine, v)

togglePaneNode :: Ident -> ViewTreeSub -> (ToggleStatus, ViewTreeSub)
togglePaneNode ident (TreeLeaf v) =
  second TreeLeaf (togglePaneView ident v)
togglePaneNode _ t =
  (Pristine, t)

togglePane :: Ident -> ViewTree -> ToggleResult ViewTree
togglePane ident =
  uncurry checkToggleResult . depthTraverseTree openPinnedSubs (togglePaneView ident)

togglePaneOpenTraversal' ::
  Traversal' a ViewTree ->
  Ident ->
  a ->
  ToggleResult a
togglePaneOpenTraversal' lens =
  mapMOf lens . togglePane

ensurePaneViewOpen :: Ident -> PaneView -> (ToggleStatus, PaneView)
ensurePaneViewOpen ident (View i s g (Pane False p c)) | ident == i =
  (Opened, View i s g (Pane True p c))
ensurePaneViewOpen ident v@(View i _ _ _) | ident == i =
  (Consistent, v)
ensurePaneViewOpen _ v =
  (Pristine, v)

ensurePaneOpen :: Ident -> ViewTree -> ToggleResult ViewTree
ensurePaneOpen ident =
  uncurry checkToggleResult . depthTraverseTree openPinnedSubs (ensurePaneViewOpen ident)

ensurePaneOpenTraversal ::
  Traversal a (ToggleResult a) ViewTree (ToggleResult ViewTree) ->
  Ident ->
  a ->
  ToggleResult a
ensurePaneOpenTraversal lens =
  over lens . ensurePaneOpen

ensurePaneOpenTraversal' ::
  Traversal' a ViewTree ->
  Ident ->
  a ->
  ToggleResult a
ensurePaneOpenTraversal' lens =
  mapMOf lens . ensurePaneOpen

skipFold ::
  Traversable t =>
  (a -> (ToggleStatus, a)) ->
  ToggleStatus ->
  t a ->
  (ToggleStatus, t a)
skipFold f =
  mapAccumL skipper
  where
    skipper Pristine a =
      f a
    skipper status a =
      (status, a)

isOpenPaneNode :: ViewTreeSub -> Bool
isOpenPaneNode =
  anyOf (TreeSub.leafData . View.extra . Pane.open) id

openPinnedPaneView :: PaneView -> (ToggleStatus, PaneView)
openPinnedPaneView (View i s g (Pane False True c)) =
  (Opened, View i s g (Pane True True c))
openPinnedPaneView v =
  (Pristine, v)

openFirstPinnedPaneNode :: ViewTreeSub -> (ToggleStatus, ViewTreeSub)
openFirstPinnedPaneNode (TreeLeaf v) =
  second TreeLeaf (openPinnedPaneView v)
openFirstPinnedPaneNode a =
  (Pristine, a)

openPaneView :: PaneView -> (ToggleStatus, PaneView)
openPaneView (View i s g (Pane False p c)) =
  (Opened, View i s g (Pane True p c))
openPaneView v =
  (Pristine, v)

openFirstPaneNode :: ViewTreeSub -> (ToggleStatus, ViewTreeSub)
openFirstPaneNode (TreeLeaf v) =
  second TreeLeaf (openPaneView v)
openFirstPaneNode a =
  (Pristine, a)

-- TODO recurse when opening pane
toggleLayoutNode :: Ident -> ToggleStatus -> ViewTree -> (ToggleStatus, ViewTree)
toggleLayoutNode ident previous (Tree v@(View i (ViewState minimized) g l) sub) | ident == i =
  first (previous <>) (if open then toggleMinimized else openPane')
  where
    open =
      any isOpenPaneNode sub
    toggleMinimized =
      (Minimized, Tree (View i (ViewState (not minimized)) g l) sub)
    openPane' =
      second (Tree v) (uncurry regularIfPristine openFirstPinned)
    openFirstPinned =
      skipFold openFirstPinnedPaneNode Pristine sub
    openFirstRegular =
      skipFold openFirstPaneNode Pristine sub
    regularIfPristine Pristine _ =
      openFirstRegular
    regularIfPristine status a =
      (status, a)
toggleLayoutNode _ a t =
  (a, t)

toggleLayout :: Ident -> ViewTree -> ToggleResult ViewTree
toggleLayout ident =
  uncurry checkToggleResult . depthTraverseTree (uncurry openPinnedSubs .: toggleLayoutNode ident) (Pristine,)

toggleLayoutOpenTraversal' ::
  Traversal' a ViewTree ->
  Ident ->
  a ->
  ToggleResult a
toggleLayoutOpenTraversal' lens =
  mapMOf lens . toggleLayout
