
import SwiftUI
import Combine

public enum RefreshState {
  case normal   // Wait for scrolling
  case primed   // Scroll beyond the threshold
  case loading  // Do the refreshing
}

public struct RefreshableScrollView<Content: View, Progress: View, BottomProgress: View>: View {
  public typealias RefreshComplete = () -> Void
  /// `RefreshComplete` passed to `OnRefresh` should be called by the user.
  public typealias OnRefresh = (@escaping RefreshComplete) -> Void
  public typealias ProgressBuilder = (RefreshState) -> Progress
  public typealias BottomProgressBuilder = (RefreshState) -> BottomProgress
  
  let topRefreshable: Bool
  private let bottomRefreshable: Bool
  
  var threshold: CGFloat = 68
  
  let onRefresh: OnRefresh?
  let onBottomRefresh: OnRefresh?
  
  let progress: ProgressBuilder?
  let bottomProgress: BottomProgressBuilder?
  
  let content: () -> Content
  
  @State private var scrollOffset: CGFloat = 0
  @State private var state = RefreshState.normal
  @State private var bottomState = RefreshState.normal
  @State private var contentBound: CGRect = .zero
  
  public init(
    topRefreshable: Bool = true,
    bottomRefreshable: Bool = true,
    threshold: CGFloat = 68,
    onRefresh: @escaping OnRefresh,
    onBottomRefresh: @escaping OnRefresh,
    @ViewBuilder progress: @escaping ProgressBuilder,
    @ViewBuilder bottomProgress: @escaping BottomProgressBuilder,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.topRefreshable = topRefreshable
    self.bottomRefreshable = bottomRefreshable
    
    self.threshold = threshold
    self.onRefresh = onRefresh
    self.onBottomRefresh = onBottomRefresh
    
    self.progress = progress
    self.bottomProgress = bottomProgress
    
    self.content = content
  }
  
  public var body: some View {
    ScrollView(.vertical) {
      
      ZStack(alignment: .top) {
        if topRefreshable, let progress = progress {
          progress(state)
            .frame(height: threshold).fixedSize()
            .offset(y: (state == .loading) ? -scrollOffset : -threshold)
        }
        
        MovingView()
        
        VStack {
          content()
            .anchorPreference(
              key: ContentPrefKey.self, value: .bounds,
              transform: { [ContentPrefData(vType: .contentView, bound: $0)] }
            )
          
          if bottomRefreshable, let bottomProgress = bottomProgress {
            bottomProgress(bottomState)
          }
        }
        .alignmentGuide(.top, computeValue: { _ in
          (state == .loading) ? -threshold + scrollOffset : 0
        })
      }
    }
    .backgroundPreferenceValue(ContentPrefKey.self) { (data: ContentPrefKey.Value) in
      GeometryReader { proxy -> FixedView in
        if bottomRefreshable {
          if let anchor = data.first(where: { $0.vType == .contentView }) {
            DispatchQueue.main.async {
              contentBound = proxy[anchor.bound]
            }
          }
        }
        
        return FixedView() /// `FixedView` is the same size with `ScrollView`
      }
    }
    .onPreferenceChange(TopPrefKey.self) { (data: TopPrefKey.Value) in
      refreshing(values: data)
    }
  }
}

extension RefreshableScrollView {
  func refreshing(values: TopPrefKey.Value) {
    let movingBound = values.first { $0.vType == .movingView }?.bound ?? .zero
    let fixedBound = values.first { $0.vType == .fixedView }?.bound ?? .zero
    scrollOffset = movingBound.minY - fixedBound.minY
    
    if topRefreshable, let onRefresh = onRefresh {
      if state != .loading {
        if scrollOffset > threshold && state == .normal {
          state = .primed
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        else if scrollOffset < threshold && state == .primed {
          state = .loading
          
          onRefresh {
            withAnimation { state = .normal }
          }
        }
      }
    }
    
    if bottomRefreshable, contentBound.height > 0, let onBottomRefresh = onBottomRefresh {
      if bottomState != .loading {
        print("TH: \(-(contentBound.height - fixedBound.height + threshold))")
        print("OF: \(scrollOffset)")
        if scrollOffset < -(contentBound.height - fixedBound.height + threshold) && bottomState == .normal {
          bottomState = .primed
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        else if scrollOffset > -(contentBound.height - fixedBound.height + threshold) && bottomState == .primed {
          bottomState = .loading
          
          onBottomRefresh {
            withAnimation { bottomState = .normal }
          }
        }
      }
    }
  }
}

struct MovingView: View {
  var body: some View {
    GeometryReader {
      Color.clear
        .preference(key: TopPrefKey.self, value: [TopPrefData(vType: .movingView, bound: $0.frame(in: .global))])
    }
    .frame(height: 0)
  }
}

struct FixedView: View {
  var body: some View {
    GeometryReader {
      Color.clear
        .preference(key: TopPrefKey.self, value: [TopPrefData(vType: .fixedView, bound: $0.frame(in: .global))])
    }
  }
}

public extension RefreshableScrollView where BottomProgress == EmptyView {
  // Top refresh only
  init(
    threshold: CGFloat = 68,
    onRefresh: @escaping OnRefresh,
    @ViewBuilder progress: @escaping ProgressBuilder,
    @ViewBuilder content: @escaping () -> Content
  ) {
    topRefreshable = true
    bottomRefreshable = false
    self.threshold = threshold
    self.onRefresh = onRefresh
    onBottomRefresh = nil
    self.progress = progress
    bottomProgress = nil
    self.content = content
  }
}

public extension RefreshableScrollView where Progress == EmptyView {
  // Bottom refresh only
  init(
    threshold: CGFloat = 68,
    onBottomRefresh: @escaping OnRefresh,
    @ViewBuilder bottomProgress: @escaping BottomProgressBuilder,
    @ViewBuilder content: @escaping () -> Content
  ) {
    topRefreshable = false
    bottomRefreshable = true
    self.threshold = threshold
    onRefresh = nil
    self.onBottomRefresh = onBottomRefresh
    progress = nil
    self.bottomProgress = bottomProgress
    self.content = content
  }
}

#if compiler(>=5.5)
@available(iOS 15.0, *)
public extension RefreshableScrollView {
  init(
    topRefreshable: Bool = true,
    bottomRefreshable: Bool = false,
    threshold: CGFloat = 68,
    onRefresh: @escaping @Sendable () async -> Void,
    onBottomRefresh: @escaping @Sendable () async -> Void,
    @ViewBuilder progress: @escaping ProgressBuilder,
    @ViewBuilder bottomProgress: @escaping BottomProgressBuilder,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.init(
      topRefreshable: topRefreshable,
      bottomRefreshable: bottomRefreshable,
      threshold: threshold,
      onRefresh: { refreshComplete in
        Task {
          await onRefresh()
          refreshComplete()
        }
      },
      onBottomRefresh: { refreshComplete in
        Task {
          await onBottomRefresh()
          refreshComplete()
        }
      },
      progress: progress,
      bottomProgress: bottomProgress,
      content: content)
  }
}
#endif
