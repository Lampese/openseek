///|
priv struct HtmlDiagramMount {
  root : @dom.Element
  renderers : DiagramRenderers
  viewports : @diagram_viewport.DiagramViewports
}

///|
fn HtmlDiagramMount::dispose(self : Self) -> Unit {
  self.renderers.dispose()
  self.viewports.dispose()
}

///|
priv suberror GithubHtmlSubscription {
  GithubHtmlSubscription
}

///|
/// The file editor owns PR details and Review comments. Reuse the transcript's
/// diagram renderers here while leaving its image/scroll observers scoped to
/// chat. Every removed comment disposes pending renders and viewport controls.
pub fn github_html_subscription() -> @sub.Sub {
  @sub.custom_sub("github-html", @sub.Local, GithubHtmlSubscription, (_, _) => {
    guard @dom.document().get_document_element() is Some(document_root) else {
      return None
    }
    let mounts : Ref[Array[HtmlDiagramMount]] = Ref([])
    let refresh = () => {
      let roots = document_root.query_selector_all(
        ".github-detail .markdown, .github-review-markdown",
      )
      let dark_mode = document_root.get_attribute("data-theme") is Some("dark")
      let retained : Array[HtmlDiagramMount] = []
      for mount in mounts.val {
        if roots.iter().any(root => root.is_same_node(mount.root.as_node())) {
          retained.push(mount)
        } else {
          mount.dispose()
        }
      }
      for root in roots {
        if !retained.any(mount => root.is_same_node(mount.root.as_node())) {
          retained.push({
            root,
            renderers: DiagramRenderers(() => ()),
            viewports: @diagram_viewport.DiagramViewports(root, () => ()),
          })
        }
      }
      for mount in retained {
        mount.renderers.refresh(mount.root, dark_mode~)
        mount.viewports.refresh()
      }
      mounts.val = retained
    }
    let observer = @dom.MutationObserver::new((_, _) => refresh())
    refresh()
    observer.observe(document_root.as_node(), child_list=true, subtree=true, attribute_filter=[
      "data-theme", "data-transcript-diagram", "data-transcript-diagram-source",
    ])
    Some({
      unload: _ => {
        observer.disconnect()
        for mount in mounts.val {
          mount.dispose()
        }
        mounts.val = []
      },
      update_tagger: _ => (),
    })
  })
}
