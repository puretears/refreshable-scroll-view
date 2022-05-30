
import SwiftUI
import Combine

public enum RefreshState {
  case normal   // Wait for scrolling
  case primed   // Scroll beyond the threshold
  case loading  // Do the refreshing
  case failed
  case successed
}

public struct RefreshableScrollView<Content: View, Progress: View, BottomProgress: View>: View {
//  public typealias RefreshComplete = () -> Void
  /// `RefreshComplete` passed to `OnRefresh` should be called by the user.
  public typealias OnRefresh = () async throws -> Void
  public typealias ProgressBuilder = (RefreshState, CGFloat) -> Progress
  public typealias BottomProgressBuilder = (RefreshState, CGFloat) -> BottomProgress
  
  let topRefreshable: Bool
  private let bottomRefreshable: Bool
  
  var threshold: CGFloat = 68
  
  let onRefresh: OnRefresh?
  let onBottomRefresh: OnRefresh?
  
  let progress: ProgressBuilder?
  let bottomProgress: BottomProgressBuilder?
  
  let bottomPadding: CGFloat
  
  let content: () -> Content
  
  @State private var topScrollOffset: CGFloat = 0
  @State private var bottomScrollOffset: CGFloat = 0
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
    bottomPadding: CGFloat = 0,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.topRefreshable = topRefreshable
    self.bottomRefreshable = bottomRefreshable
    
    self.threshold = threshold
    self.onRefresh = onRefresh
    self.onBottomRefresh = onBottomRefresh
    
    self.progress = progress
    self.bottomProgress = bottomProgress
    
    self.bottomPadding = bottomPadding
    self.content = content
  }
  
  public var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      ZStack(alignment: .top) {
        if topRefreshable, let progress = progress {
          progress(state, topScrollOffset)
            .frame(height: threshold)
            .offset(y: (state == .loading || state == .successed || state == .failed) ? -topScrollOffset : -threshold)
        }
        
        MovingView()
        
        VStack {
          content()
          
          if bottomRefreshable, let bottomProgress = bottomProgress {
            bottomProgress(bottomState, bottomScrollOffset)
//              .frame(height: threshold)
          }
        }
        .anchorPreference(
          key: ContentPrefKey.self, value: .bounds,
          transform: { [ContentPrefData(vType: .contentView, bound: $0)] }
        )
        .alignmentGuide(.top, computeValue: { _ in
          (state == .loading || state == .successed || state == .failed) ? -threshold + topScrollOffset : 0
        })
        // End VStack
      }
      .ignoresSafeArea(edges: .bottom)
      .padding(.bottom, bottomPadding)
      // End ZStack(alignment: .top)
    }
    .frame(alignment: .top)
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
    let currentScrollOffset = movingBound.minY - fixedBound.minY
    
    topScrollOffset = currentScrollOffset
    bottomScrollOffset = currentScrollOffset
    
    if topRefreshable, let onRefresh = onRefresh {
      if state != .loading {
        if topScrollOffset > threshold && state == .normal {
          state = .primed
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        else if topScrollOffset < threshold && state == .primed {
          state = .loading
          
          Task {
            do {
              try await onRefresh()
              withAnimation(.default) { state = .successed }
              withAnimation(.default.delay(0.3)) { state = .normal }
            }
            catch {
              withAnimation { state = .failed }
              withAnimation(.default.delay(0.4)) { state = .normal }
            }
          }
        }
      }
    }
    
    /* Trigger the bottom refresh manually.
    if bottomRefreshable, contentBound.height > 0, let onBottomRefresh = onBottomRefresh {
      bottomScrollOffset += (contentBound.height - fixedBound.height)
      
      if bottomState != .loading {
        if bottomScrollOffset < -threshold / 2 && bottomState == .normal {
          bottomState = .primed
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        else if bottomScrollOffset >= 0 && bottomState == .primed {
          bottomState = .loading

          Task {
            do {
              try await onBottomRefresh()
              withAnimation { bottomState = .successed }
              withAnimation(.default.delay(0.5)) { bottomState = .normal }
            }
            catch {
              withAnimation { bottomState = .failed }
              withAnimation(.default.delay(0.5)) { bottomState = .normal }
            }
          }
        }
      }
    }
    */
    if bottomRefreshable, contentBound.height > 0, let onBottomRefresh = onBottomRefresh {
      if bottomState != .loading {
        if bottomScrollOffset <= -(contentBound.height - fixedBound.height) * 0.5 {
          bottomState = .loading

          Task {
            do {
              try await onBottomRefresh()
              withAnimation { bottomState = .successed }
              withAnimation(.default.delay(0.5)) { bottomState = .normal }
            }
            catch {
              withAnimation { bottomState = .failed }
              withAnimation(.default.delay(0.5)) { bottomState = .normal }
            }
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
    bottomPadding = 0
    self.content = content
  }
}

public extension RefreshableScrollView where Progress == EmptyView {
  // Bottom refresh only
  init(
    threshold: CGFloat = 68,
    onBottomRefresh: @escaping OnRefresh,
    bottomPadding: CGFloat = 0,
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
    self.bottomPadding = bottomPadding
    self.content = content
  }
}
