# 帖子详情页滚动掉帧 — 排查记录

记录于 2026-04-20。结论来自代码静态分析,**尚未经 Instruments 验证**。

## 三个最可能的瓶颈(按可能性排序)

### 1. cell 高度走 `automaticDimension`,滚动时同步排版

`PostNativeCell` 配合 `UITableView.automaticDimension`(见 `dexo/Features/ForumDetail/TopicDetail/PostNativeCell.swift:256-262` 附近的高度配置)。tableView 滚动到一个长贴 cell 时,会同步触发 `systemLayoutSizeFitting`,需要 autolayout 求解整个 stack view + Core Text 全量排版,容易超 16.6ms 帧预算。

### 2. cell 复用时重新跑 `NativeContentRenderer.renderBlocks()`

`PostNativeCell.swift:565-592` 的 Tier 3(完整渲染)路径在 `configure` 时重建 stack view 子视图、为每个 paragraph 构造 `NSAttributedString`、批量加载 inline emoji。长贴 20+ block 时,主线程被堵在配置上;`TopicDetailViewModel.swift:380-384` 也参与这条链路。

### 3. 每段都新建 `LinkTextView`,无复用池

`dexo/Features/ForumDetail/TopicDetail/NativeContent/ParagraphRenderer.swift:24-38` 每渲染一段就 alloc 一个 `LinkTextView`。LinkTextView 设置 `attributedText` 触发 Core Text 初次排版,有 spoiler 时还要枚举 range 加模糊层。长贴反复 alloc 累积开销大。

## 验证方法

跑 Instruments **Time Profiler**,录 2–3 秒快速滚动,看主线程采样里这三者占比:
- `systemLayoutSizeFitting` / `-[NSISEngine ...]` (autolayout)
- `-[NSLayoutManager _layout...]` / `CTTypesetter...` (Core Text)
- `renderBlocks` / `configure` 自己的栈帧

辅助:**System Trace** 找持续 >25ms 的主线程阻塞;**Allocations** 看一次滚动里 `UITextView`/`NSAttributedString` 的分配次数。

## 与 "Parsing HTML Fast" 文章的关系

文章核心是把 SwiftSoup 换成自写 tokenizer 跳过 DOM tree 构造,在 Mastodon 短文本流上拿到 ~2.7× 解析提速。**对本项目滚动掉帧相关性低**:

- 我们瓶颈不在 HTML→AST,在下游的 cell 配置(autolayout + Core Text + view alloc)。
- CookedHTML 需要识别 quote / onebox / table / 列表等 Discourse 结构,**必须有树**,token 流不够。换解析器风险大、收益小。
- 唯一沾边的思路是"把 NSAttributedString 构造搬到后台预渲染" — 但收益来自换线程,不是换解析器。

## 可能的优化方向(待验证后再选)

- 高度预缓存(根据 `cooked` HTML hash → cell 高度)
- 后台预渲染 `NSAttributedString`,主线程只 set
- `LinkTextView` 复用池,避免反复 alloc
- 长贴按段懒加载或按屏幕外裁剪
