import Foundation

public struct LaTeXTemplate: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let icon: String
    public let category: String
    public let content: String

    public init(
        id: String,
        name: String,
        subtitle: String,
        icon: String,
        category: String = "LaTeX3 Core",
        content: String
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.content = content
    }
}

public struct LaTeXSnippet: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let description: String
    public let code: String
}

public struct LaTeXPackagePreset: Identifiable, Sendable {
    public let id: String
    public let package: String
    public let options: String
    public let category: String
    public let description: String

    public var usepackageStatement: String {
        if options.isEmpty {
            return "\\usepackage{\(package)}"
        } else {
            return "\\usepackage[\(options)]{\(package)}"
        }
    }
}

public enum LaTeXCatalog {
    public static let defaultTemplate = templates[0]

    public static let templates: [LaTeXTemplate] = [
        LaTeXTemplate(
            id: "expl3-showcase",
            name: "LaTeX3 (expl3 + xparse) Showcase",
            subtitle: "Algorithmic macros, token lists, sequences, and modern typography",
            icon: "function",
            content: #"""
\documentclass[11pt,a4paper]{article}

% --- Modern Typography & Geometry ---
\usepackage[margin=1in]{geometry}
\usepackage{amsmath,amssymb,amsthm}
\usepackage{mathtools}
\usepackage{booktabs}
\usepackage{xcolor}
\usepackage{hyperref}

% --- LaTeX3 Programming Layer ---
\usepackage{expl3}
\usepackage{xparse}

\definecolor{accent}{RGB}{32, 96, 192}
\definecolor{codebg}{RGB}{245, 247, 250}

\hypersetup{
  colorlinks=true,
  linkcolor=accent,
  urlcolor=accent,
  citecolor=accent
}

% =============================================================================
% LaTeX3 (expl3) Module: \l_latexap_* and algorithmic helpers
% =============================================================================
\ExplSyntaxOn

% 1. Integer step & factorial evaluation using l3int
\NewDocumentCommand{\ExpandFactorial}{ m }
  {
    \int_eval:n { #1 } ! = 
    \int_step_inline:nnnn { 1 } { 1 } { #1 }
      {
        ##1 \int_compare:nNnTF { ##1 } < { #1 } { \times } { }
      }
    = \int_eval:n { \latexap_factorial:n { #1 } }
  }

\cs_new:Npn \latexap_factorial:n #1
  {
    \int_compare:nNnTF { #1 } < { 2 }
      { 1 }
      { #1 * \latexap_factorial:n { \int_eval:n { #1 - 1 } } }
  }

% 2. Comma-list processing with l3clist and l3seq
\seq_new:N \l_latexap_items_seq

\NewDocumentCommand{\BadgeList}{ O{accent} m }
  {
    \seq_set_from_clist:Nn \l_latexap_items_seq { #2 }
    \seq_map_inline:Nn \l_latexap_items_seq
      {
        \colorbox{#1!12}{\textcolor{#1}{\texttt{\strut ##1}}}
        \hspace{4pt}
      }
  }

% 3. Floating-point table generator using l3fp
\NewDocumentCommand{\HarmonicRow}{ m }
  {
    #1 &
    $\frac{1}{#1}$ &
    \fp_eval:n { round(1 / #1, 5) } &
    \fp_eval:n { round(ln(#1 + 1), 5) } \\
  }

% 4. Custom xparse callout environment
\NewDocumentEnvironment{CalloutBox}{ O{Note} m }
  {
    \par\medskip\noindent
    \begin{tabular}{|p{0.94\textwidth}}
    \textbf{\textcolor{accent}{#1 — #2}}\\[2pt]
  }
  {
    \end{tabular}\par\medskip
  }

\ExplSyntaxOff
% =============================================================================

\title{\textbf{Modern \LaTeX3 Document Engineering}\\[4pt]
\large Powered by \texttt{expl3}, \texttt{xparse}, and Live Tectonic Rendering}
\author{LaTeXaP Studio for macOS}
\date{\today}

\begin{document}

\maketitle

\begin{abstract}
Welcome to \textbf{LaTeXaP}, a native macOS studio engineered for \LaTeX3 document authoring. Edit any part of this source file to trigger automatic live compilation via the embedded \emph{Tectonic} engine, or \textbf{Command-Click} in the PDF preview to jump directly between source lines and rendered output via SyncTeX.
\end{abstract}

\section{LaTeX3 (\texttt{expl3}) Core Capabilities}

The \LaTeX3 programming layer (\texttt{expl3}) introduces a structured, namespace-safe syntax where whitespace is ignored and function signatures explicitly declare argument expansion (\texttt{:N}, \texttt{:n}, \texttt{:V}, \texttt{:x}, \texttt{:f}).

\noindent
\BadgeList{l3kernel, l3packages, xparse, l3int, l3fp, l3seq, l3clist, l3keys}

\subsection{Compile-Time Integer Recursion (\texttt{l3int})}

Using \verb|\ExpandFactorial{n}| defined in our \texttt{\textbackslash ExplSyntaxOn} block:
\begin{align}
  \ExpandFactorial{5} \\
  \ExpandFactorial{7}
\end{align}

\begin{CalloutBox}[Tip]{Interactive SyncTeX Navigation}
Hold \textbf{\(\mathcal{H}\) Command} and click anywhere on this PDF page to jump to the corresponding line in the editor, or click the \textbf{Sync PDF} button in the toolbar to highlight your cursor's position in the PDF.
\end{CalloutBox}

\section{Floating-Point Engine (\texttt{l3fp}) \& Booktabs}

The \texttt{l3fp} module provides IEEE 754 decimal floating-point arithmetic directly inside \TeX{} without external scripts:

\begin{center}
\begin{tabular}{@{}cccc@{}}
\toprule
\textbf{Index $n$} & \textbf{Term $1/n$} & \textbf{Decimal (\texttt{l3fp})} & \textbf{$\ln(n+1)$} \\
\midrule
\HarmonicRow{1}
\HarmonicRow{2}
\HarmonicRow{3}
\HarmonicRow{4}
\HarmonicRow{5}
\bottomrule
\end{tabular}
\end{center}

\section{Mathematical Typesetting}

Let $\mathcal{F}\{f(t)\} = \hat{f}(\omega)$ denote the unitary Fourier transform:
\begin{equation}
  \hat{f}(\omega) = \frac{1}{\sqrt{2\pi}} \int_{-\infty}^{\infty} f(t)\, e^{-i\omega t}\,\mathrm{d}t,
  \qquad
  \sum_{k=1}^{\infty} \frac{1}{k^2} = \frac{\pi^2}{6}.
\end{equation}

\end{document}
"""#
        ),
        LaTeXTemplate(
            id: "academic-paper",
            name: "Academic Research Article",
            subtitle: "Two-column IEEE/ACM-ready article with spanning abstract, theorems, math, and bibliography",
            icon: "doc.richtext",
            content: #"""
\documentclass[10pt,twocolumn,a4paper]{article}
\usepackage[top=0.85in,bottom=0.9in,left=0.7in,right=0.7in,columnsep=0.28in]{geometry}
\usepackage{amsmath,amssymb,amsthm}
\usepackage{mathtools}
\usepackage{booktabs}
\usepackage{xcolor}
\usepackage{hyperref}
\usepackage{expl3}
\usepackage{xparse}

\definecolor{citeblue}{RGB}{20, 80, 165}
\hypersetup{
  colorlinks=true,
  linkcolor=citeblue,
  citecolor=citeblue,
  urlcolor=citeblue
}

\newtheorem{theorem}{Theorem}
\newtheorem{lemma}[theorem]{Lemma}
\newtheorem{proposition}[theorem]{Proposition}
\theoremstyle{definition}
\newtheorem{definition}{Definition}
\newtheorem{assumption}{Assumption}

% =============================================================================
% LaTeX3 (expl3 + xparse) Mathematical & Author Macros
% =============================================================================
\ExplSyntaxOn

% Paired norm with optional star for auto-sizing: \norm{x} or \norm*{x}
\NewDocumentCommand{\norm}{ s m }
  {
    \IfBooleanTF{#1}
      { \left\lVert #2 \right\rVert }
      { \lVert #2 \rVert }
  }

% Inner product: \ip{x}{y} or \ip*{x}{y}
\NewDocumentCommand{\ip}{ s m m }
  {
    \IfBooleanTF{#1}
      { \left\langle #2, #3 \right\rangle }
      { \langle #2, #3 \rangle }
  }

\NewDocumentCommand{\R}{}{ \mathbb{R} }
\NewDocumentCommand{\E}{}{ \mathbb{E} }

% Comma-separated keywords helper using l3clist
\clist_new:N \l_paper_keywords_clist
\NewDocumentCommand{\Keywords}{ m }
  {
    \par\vspace{4pt}\noindent
    \textbf{\small Keywords:\space}
    \footnotesize
    \clist_set:Nn \l_paper_keywords_clist { #1 }
    \clist_use:Nn \l_paper_keywords_clist { \space$\cdot$\space }
  }

\ExplSyntaxOff
% =============================================================================

\title{\vspace{-1.2em}\Large\textbf{Accelerated First-Order Methods Under Generalized Smoothness:}\\
\large\textbf{Non-Asymptotic Convergence and Minimax Lower Bounds}}

\author{
  \begin{tabular}[t]{c}
    \textbf{Jane Doe}$^{1}$ \\[2pt]
    \small Department of Mathematics \\
    \small Stanford University \\
    \footnotesize\texttt{janedoe@stanford.edu}
  \end{tabular}
  \hspace{2.2em}
  \begin{tabular}[t]{c}
    \textbf{John Smith}$^{2}$ \\[2pt]
    \small Computer Science \& Artificial Intelligence Lab \\
    \small Massachusetts Institute of Technology \\
    \footnotesize\texttt{jsmith@csail.mit.edu}
  \end{tabular}
}
\date{\small \today}

\begin{document}

% Full-width title and spanning abstract across both columns
\twocolumn[
  \begin{@twocolumnfalse}
    \maketitle
    \vspace{-0.8em}
    \begin{center}
      \begin{minipage}{0.92\textwidth}
        \hrule height 0.6pt
        \vspace{6pt}
        \noindent\textbf{\small Abstract.}\space
        \small
        We study the non-asymptotic convergence of accelerated first-order optimization algorithms for smooth, strongly convex objectives in high-dimensional Euclidean spaces. Using modern \LaTeX3 (\texttt{expl3} and \texttt{xparse}) semantic macros, we establish a unified Lyapunov potential analysis that bridges standard gradient descent and Nesterov's accelerated gradient method. Our bounds achieve the optimal $\mathcal{O}(\sqrt{\kappa}\log(1/\epsilon))$ oracle complexity and are validated on ill-conditioned quadratic ensembles.
        \Keywords{Convex Optimization, Accelerated Gradient Methods, Lyapunov Analysis, LaTeX3}
        \vspace{6pt}
        \hrule height 0.6pt
      \end{minipage}
    \end{center}
    \vspace{1.4em}
  \end{@twocolumnfalse}
]

\section{Introduction}

First-order methods form the computational backbone of modern large-scale machine learning and scientific computing \cite{nesterov1983,polyak1964}. Consider the unconstrained minimization problem
\begin{equation}\label{eq:problem}
  \min_{x \in \R^d} f(x),
\end{equation}
where $f: \R^d \to \R$ is continuously differentiable. When the dimension $d$ exceeds $10^6$, second-order Newton steps become prohibitively expensive, motivating optimal gradient-based schemes.

\subsection{Contributions}
Our main contributions are threefold:
\begin{enumerate}
  \item We formulate a concise potential-function proof for accelerated gradient descent in Theorem~\ref{thm:convergence}.
  \item We compare oracle complexities across condition numbers $\kappa = L/\mu$ in Table~\ref{tab:rates}.
  \item We demonstrate clean \LaTeX3 (\texttt{xparse}) notation macros such as \verb|\norm*{x}| and \verb|\ip{u}{v}|.
\end{enumerate}

\section{Preliminaries \& Assumptions}

Let $\ip{x}{y} = x^\top y$ denote the standard Euclidean inner product and $\norm{x}_2 = \sqrt{\ip{x}{x}}$ the induced norm.

\begin{assumption}[$L$-Smoothness and $\mu$-Strong Convexity]\label{assump:smooth}
There exist constants $0 < \mu \le L < \infty$ such that for all $x, y \in \R^d$:
\begin{align}
  f(y) &\ge f(x) + \ip{\nabla f(x)}{y - x} + \frac{\mu}{2}\norm{y - x}_2^2, \\
  f(y) &\le f(x) + \ip{\nabla f(x)}{y - x} + \frac{L}{2}\norm{y - x}_2^2.
\end{align}
\end{assumption}

We define the condition number of $f$ as $\kappa \coloneqq L / \mu \ge 1$.

\section{Main Convergence Results}

Consider the Nesterov Accelerated Gradient (NAG) updates initialized at $x_0 = y_0 \in \R^d$:
\begin{subequations}\label{eq:nag}
\begin{align}
  x_{k+1} &= y_k - \frac{1}{L} \nabla f(y_k), \\
  y_{k+1} &= x_{k+1} + \frac{\sqrt{\kappa} - 1}{\sqrt{\kappa} + 1}(x_{k+1} - x_k).
\end{align}
\end{subequations}

\begin{theorem}[Accelerated Linear Convergence]\label{thm:convergence}
Suppose Assumption~\ref{assump:smooth} holds and let $x^\star = \arg\min_{x \in \R^d} f(x)$. Then the iterates $\{x_k\}_{k \ge 0}$ generated by \eqref{eq:nag} satisfy
\begin{equation}
  f(x_k) - f(x^\star) \le \left(1 - \frac{1}{\sqrt{\kappa}}\right)^k
  \left( f(x_0) - f(x^\star) + \frac{\mu}{2}\norm*{x_0 - x^\star}_2^2 \right).
\end{equation}
\end{theorem}

\begin{proof}
Define the discrete Lyapunov energy functional
\[
  \mathcal{V}_k \coloneqq f(x_k) - f(x^\star) + \frac{\mu}{2}\norm*{v_k - x^\star}_2^2.
\]
By strong convexity and the $L$-smooth descent lemma, $\mathcal{V}_{k+1} \le (1 - \kappa^{-1/2})\mathcal{V}_k$. Unrolling the recursion over $k$ steps completes the proof.
\end{proof}

\section{Empirical \& Theoretical Comparison}

Table~\ref{tab:rates} summarizes the iteration complexity required to reach an $\epsilon$-suboptimal solution $f(x_k) - f(x^\star) \le \epsilon$.

\begin{table}[htbp]
  \centering
  \caption{Oracle complexity and convergence rates for $\mu$-strongly convex, $L$-smooth objectives ($\kappa = L/\mu$).}
  \label{tab:rates}
  \vspace{4pt}
  \footnotesize
  \begin{tabular}{@{}lcc@{}}
    \toprule
    \textbf{Algorithm} & \textbf{Contraction Factor} & \textbf{Oracle Calls} \\
    \midrule
    Gradient Descent & $1 - \kappa^{-1}$ & $\mathcal{O}(\kappa \log(1/\epsilon))$ \\
    Heavy Ball \cite{polyak1964} & $1 - 2\kappa^{-1/2}$ (local) & $\mathcal{O}(\sqrt{\kappa} \log(1/\epsilon))$ \\
    Nesterov AGD \cite{nesterov1983} & $1 - \kappa^{-1/2}$ (global) & $\mathcal{O}(\sqrt{\kappa} \log(1/\epsilon))$ \\
    \bottomrule
  \end{tabular}
\end{table}

\section{Conclusion}

We have shown how \LaTeX3 (\texttt{expl3} and \texttt{xparse}) macros streamline mathematical typesetting in two-column research articles while maintaining full compatibility with standard \LaTeX{} classes.

\begin{thebibliography}{9}
\footnotesize
\bibitem{nesterov1983}
Y.~Nesterov, ``A method for solving the convex programming problem with convergence rate $\mathcal{O}(1/k^2)$,'' \emph{Soviet Mathematics Doklady}, vol.~27, no.~2, pp.~372--376, 1983.

\bibitem{polyak1964}
B.~T.~Polyak, ``Some methods of speeding up the convergence of iteration methods,'' \emph{USSR Computational Mathematics and Mathematical Physics}, vol.~4, no.~5, pp.~1--17, 1964.
\end{thebibliography}

\end{document}
"""#
        ),
        LaTeXTemplate(
            id: "tikz-graphics",
            name: "TikZ & PGF Vector Diagrams",
            subtitle: "Vector diagrams, commutative diagrams, and algorithmic TikZ loops",
            icon: "scribble.variable",
            content: #"""
\documentclass[11pt,a4paper]{article}
\usepackage[margin=1in]{geometry}
\usepackage{amsmath,amssymb}
\usepackage{tikz}
\usetikzlibrary{arrows.meta,positioning,calc}
\usepackage{expl3}
\usepackage{xparse}

\title{\textbf{Programmatic Vector Graphics with TikZ \& \LaTeX3}}
\author{LaTeXaP}
\date{\today}

\begin{document}
\maketitle

\section{State Machine Diagram}
\begin{center}
\begin{tikzpicture}[
  node distance=2.6cm,
  >={Stealth[round]},
  state/.style={circle, draw=blue!70!black, fill=blue!8, thick, minimum size=1.3cm, font=\bfseries}
]
  \node[state] (s0) {$q_0$};
  \node[state, right=of s0] (s1) {$q_1$};
  \node[state, right=of s1] (s2) {$q_2$};

  \draw[->, thick] (s0) edge[bend left=25] node[above] {$\alpha$} (s1);
  \draw[->, thick] (s1) edge[bend left=25] node[above] {$\beta$} (s2);
  \draw[->, thick] (s2) edge[bend left=30] node[below] {$\gamma$} (s0);
\end{tikzpicture}
\end{center}

\section{Parametric Polar Rose}
\begin{center}
\begin{tikzpicture}[scale=2.2]
  \draw[gray!30, very thin] (-1.2,-1.2) grid[step=0.4] (1.2,1.2);
  \draw[->, gray] (-1.3,0) -- (1.3,0) node[right] {$x$};
  \draw[->, gray] (0,-1.3) -- (0,1.3) node[above] {$y$};
  \draw[thick, blue!75!black, domain=0:360, samples=300, smooth, variable=\t]
    plot ({cos(3*\t)*cos(\t)}, {cos(3*\t)*sin(\t)});
\end{tikzpicture}
\end{center}

\end{document}
"""#
        ),
        LaTeXTemplate(
            id: "l3keys-package-demo",
            name: "LaTeX3 Key-Value Interface (l3keys)",
            subtitle: "Custom key-value configuration commands using \\keys_define:nn",
            icon: "slider.horizontal.3",
            content: #"""
\documentclass[11pt,a4paper]{article}
\usepackage[margin=1in]{geometry}
\usepackage{xcolor}
\usepackage{expl3}
\usepackage{xparse}

\ExplSyntaxOn

\tl_new:N \l_card_title_tl
\tl_new:N \l_card_author_tl
\tl_new:N \l_card_color_tl
\bool_new:N \l_card_border_bool

\keys_define:nn { latexap / card }
  {
    title  .tl_set:N   = \l_card_title_tl,
    title  .initial:n  = { Untitled~Component },
    author .tl_set:N   = \l_card_author_tl,
    author .initial:n  = { Anonymous },
    color  .tl_set:N   = \l_card_color_tl,
    color  .initial:n  = { blue!70!black },
    border .bool_set:N = \l_card_border_bool,
    border .initial:n  = true,
  }

\NewDocumentCommand{\RenderCard}{ O{} +m }
  {
    \group_begin:
    \keys_set:nn { latexap / card } { #1 }
    \par\medskip\noindent
    \fcolorbox
      { \bool_if:NTF \l_card_border_bool { \l_card_color_tl } { white } }
      { \l_card_color_tl ! 6 }
      {
        \begin{minipage}{0.94\textwidth}
          \vspace{4pt}
          {\large\bfseries\textcolor{\l_card_color_tl}{\tl_use:N \l_card_title_tl}}
          \hfill
          {\footnotesize\textsc{Author:~\tl_use:N \l_card_author_tl}}
          \par\vspace{4pt}\hrule\vspace{6pt}
          #2
          \vspace{4pt}
        \end{minipage}
      }
    \par\medskip
    \group_end:
  }

\ExplSyntaxOff

\title{\textbf{Declarative Key-Value APIs in \LaTeX3 (\texttt{l3keys})}}
\author{LaTeXaP}
\date{\today}

\begin{document}
\maketitle

\section{Custom \texttt{l3keys} Component Cards}

\RenderCard[title={Quantum Fourier Transform}, author={P. Shor}, color={teal!75!black}]{
  The \texttt{l3keys} module provides strongly typed key-value parsing (\texttt{.tl\_set:N}, \texttt{.int\_set:N}, \texttt{.bool\_set:N}, \texttt{.fp\_set:N}) built directly into the \LaTeX3 kernel.
}

\RenderCard[title={Zero-Border Warning Box}, author={System}, color={orange!80!black}, border=false]{
  Passing \texttt{border=false} toggles the boolean variable \texttt{\textbackslash l\_card\_border\_bool} at expansion time.
}

\end{document}
"""#
        ),
        LaTeXTemplate(
            id: "python-scientific",
            name: "Python & Scientific Computing in LaTeX3",
            subtitle: "Syntax-highlighted Python listings, algorithmic blocks, and expl3 numeric pipelines",
            icon: "terminal",
            content: #"""
\documentclass[11pt,a4paper]{article}
\usepackage[margin=1in]{geometry}
\usepackage{amsmath,amssymb}
\usepackage{xcolor}
\usepackage{listings}
\usepackage{booktabs}
\usepackage{expl3}
\usepackage{xparse}

\definecolor{pykeyword}{RGB}{155, 35, 147}
\definecolor{pystring}{RGB}{196, 26, 22}
\definecolor{pycomment}{RGB}{93, 108, 121}
\definecolor{pybg}{RGB}{248, 249, 251}

\lstdefinestyle{pythonstyle}{
  language=Python,
  backgroundcolor=\color{pybg},
  basicstyle=\ttfamily\small,
  keywordstyle=\color{pykeyword}\bfseries,
  stringstyle=\color{pystring},
  commentstyle=\color{pycomment}\itshape,
  numbers=left,
  numberstyle=\tiny\color{gray},
  frame=single,
  rulecolor=\color{black!15},
  showstringspaces=false,
  breaklines=true
}

\ExplSyntaxOn
\NewDocumentCommand{\PyInline}{ v }
  {
    \colorbox{pybg}{\texttt{\textcolor{pykeyword}{#1}}}
  }
\ExplSyntaxOff

\title{\textbf{Python \& Scientific Algorithms in \LaTeX3}}
\author{LaTeXaP}
\date{\today}

\begin{document}
\maketitle

\section{Python Implementation (\texttt{listings})}

Using \PyInline{listings} configured with a custom Python style, you can embed syntax-highlighted Python modules directly in your \LaTeX3 document:

\begin{lstlisting}[style=pythonstyle, caption={Newton-Raphson root solver in Python}]
import math
from typing import Callable

def newton_raphson(
    f: Callable[[float], float],
    df: Callable[[float], float],
    x0: float,
    tol: float = 1e-8,
    max_iter: int = 50,
) -> float:
    """Find root of f(x) = 0 starting from x0."""
    x = x0
    for _ in range(max_iter):
        fx = f(x)
        if abs(fx) < tol:
            return x
        x = x - fx / df(x)
    return x
\end{lstlisting}

\end{document}
"""#
        ),
        LaTeXTemplate(
            id: "apa7-student",
            name: "APA 7th Student Paper",
            subtitle: "Double-spaced APA 7th edition student paper with running head, abstract, and biblatex APA citations",
            icon: "doc.text",
            category: "Academic Papers",
            content: #"""
\documentclass[12pt,letterpaper]{article}
\usepackage[margin=1in]{geometry}
\usepackage{setspace}
\usepackage{fancyhdr}
\usepackage{amsmath}
\usepackage{booktabs}
\usepackage{graphicx}
\usepackage[style=authoryear,backend=bibtex]{biblatex}
\usepackage{csquotes}
\usepackage{hyperref}

\doublespacing
\pagestyle{fancy}
\fancyhf{}
\lhead{\footnotesize RUNNING HEAD: SHORT TITLE}
\rhead{\footnotesize \thepage}
\renewcommand{\headrulewidth}{0pt}

\title{\textbf{Impact of Retrieval-Augmented Study Tools on Undergraduate Academic Writing}}
\author{Student Author \\ Department of Psychology, State University \\ Course: PSYC 301 — Research Methods}
\date{\today}

\begin{document}
\maketitle

\begin{abstract}
This paper examines how structured citation workflows and real-time typesetting feedback influence clarity, citation accuracy, and adherence to APA 7th edition formatting guidelines among undergraduate researchers.
\end{abstract}

\section{Introduction}
Clear scholarly communication depends on accurate attribution of prior findings and consistent structural formatting. When students manage references manually, typographical drift frequently introduces unresolved citations and formatting inconsistencies.

\section{Method}
\subsection{Participants and Design}
Participants drafted a 1,500-word literature synthesis using either manual reference lists or integrated BibTeX workflows.

\section{Results}
Preliminary comparisons summarized in Table~\ref{tab:apa-results} indicate higher reference completeness in structured environments.

\begin{table}[htbp]
  \centering
  \caption{Comparison of Citation Accuracy Across Authoring Workflows}
  \label{tab:apa-results}
  \begin{tabular}{@{}lcc@{}}
    \toprule
    \textbf{Condition} & \textbf{Citation Errors} & \textbf{Completion (min)} \\
    \midrule
    Manual Formatting & 4.2 & 48.5 \\
    Structured LaTeX & 0.3 & 31.0 \\
    \bottomrule
  \end{tabular}
\end{table}

\section{Discussion}
Automated pre-flight validation substantially reduces avoidable submission errors prior to final grading.

\end{document}
"""#
        ),
        LaTeXTemplate(
            id: "ieee-conference",
            name: "IEEE Conference Paper",
            subtitle: "Two-column IEEE engineering conference paper with abstract, index terms, equations, and tables",
            icon: "cpu",
            category: "Academic Papers",
            content: #"""
\documentclass[conference,letterpaper]{IEEEtran}
\usepackage{amsmath,amssymb}
\usepackage{booktabs}
\usepackage{graphicx}
\usepackage{siunitx}
\usepackage[style=ieee,backend=bibtex]{biblatex}
\usepackage{hyperref}

\title{Low-Latency Deterministic Compilation Pipelines for Interactive Document Engineering}

\author{
  \IEEEauthorblockN{Alex Rivera\IEEEauthorrefmark{1} and Jordan Chen\IEEEauthorrefmark{2}}
  \IEEEauthorblockA{\IEEEauthorrefmark{1}Department of Electrical Engineering and Computer Science, Tech Institute\\
  Email: arivera@institute.edu}
  \IEEEauthorblockA{\IEEEauthorrefmark{2}Systems Research Lab, National University\\
  Email: jchen@national.edu}
}

\begin{document}
\maketitle

\begin{abstract}
We present an incremental TeX compilation architecture tailored for desktop authoring environments. By staging local bibliography and figure assets into isolated build workspaces and synchronizing PDF coordinates via SyncTeX, our pipeline achieves sub-second incremental previews without polluting source directories.
\end{abstract}

\begin{IEEEkeywords}
Typesetting systems, incremental compilation, SyncTeX, scholarly authoring.
\end{IEEEkeywords}

\section{Introduction}
Interactive engineering papers frequently combine complex mathematics, vector charts, and dense empirical tables. Waiting several seconds for full rebuilds interrupts writer flow and slows iteration.

\section{System Architecture}
Let $\tau_{\text{compile}}$ denote end-to-end build latency from source edit to PDF swap:
\begin{equation}\label{eq:latency}
  \tau_{\text{compile}} = \tau_{\text{stage}} + \tau_{\text{xetex}} + \tau_{\text{render}}.
\end{equation}
As shown in Equation~\eqref{eq:latency}, minimizing asset staging overhead $\tau_{\text{stage}}$ via validated symbolic links reduces total rebuild latency below \qty{450}{ms}.

\section{Empirical Evaluation}
Table~\ref{tab:ieee-bench} summarizes measured compilation times across document sizes.

\begin{table}[htbp]
  \centering
  \caption{Incremental Build Latency Across Document Lengths}
  \label{tab:ieee-bench}
  \begin{tabular}{@{}lcc@{}}
    \toprule
    \textbf{Document Size} & \textbf{Cold Build (ms)} & \textbf{Warm Build (ms)} \\
    \midrule
    4 Pages & 1120 & 310 \\
    12 Pages & 1840 & 465 \\
    \bottomrule
  \end{tabular}
\end{table}

\section{Conclusion}
Isolated staging paired with SyncTeX feedback yields responsive engineering paper authoring.

\end{document}
"""#
        ),
        LaTeXTemplate(
            id: "acm-article",
            name: "ACM Computing Article",
            subtitle: "ACM SIGCONF/sigplan-ready computing research manuscript with CCS structure and booktabs",
            icon: "laptopcomputer",
            category: "Academic Papers",
            content: #"""
\documentclass[sigconf,nonacm]{acmart}
\usepackage{booktabs}
\usepackage{amsmath}
\usepackage{siunitx}

\title{Human-Centered Tooling for Reproducible LaTeX Authoring}

\author{Taylor Morgan}
\affiliation{%
  \institution{University of Computing}
  \city{Seattle}
  \state{WA}
  \country{USA}
}
\email{tmorgan@computing.edu}

\begin{abstract}
Modern computer science manuscripts depend on reproducible artifact bundles, clean vector plots, and strict conference page budgets. We describe a desktop workflow that surfaces plain-English compiler diagnostics and validates submission bundles automatically.
\end{abstract}

\keywords{Authoring tools, reproducibility, LaTeX, usability}

\begin{document}
\maketitle

\section{Introduction}
Researchers routinely assemble camera-ready archives under tight conference deadlines. Uncaught absolute image paths or missing bibliography entries remain common causes of submission rejections.

\section{Design Goals}
\begin{itemize}
  \item Maintain transparent, human-editable LaTeX source code.
  \item Validate citations, cross-references, and relative figure paths continuously.
  \item Package deterministic self-contained submission archives.
\end{itemize}

\section{Evaluation}
In our formative study, participants resolved formatting diagnostics \qty{62}{\%} faster when presented with plain-English explanations alongside one-click safe source patches.

\end{document}
"""#
        ),
        LaTeXTemplate(
            id: "mla-essay",
            name: "MLA Humanities Essay",
            subtitle: "MLA 9th edition double-spaced humanities essay with student header, block quotes, and MLA style",
            icon: "text.book.closed",
            category: "Academic Papers",
            content: #"""
\documentclass[12pt,letterpaper]{article}
\usepackage[margin=1in]{geometry}
\usepackage{setspace}
\usepackage{fancyhdr}
\usepackage[style=mla,backend=bibtex]{biblatex}
\usepackage{csquotes}
\usepackage{hyperref}

\doublespacing
\setlength{\parindent}{0.5in}

\pagestyle{fancy}
\fancyhf{}
\rhead{Lastname \thepage}
\renewcommand{\headrulewidth}{0pt}

\begin{document}

\noindent
First Lastname\\
Professor Name\\
ENGL 210: Modern Literature\\
\today

\begin{center}
Narrative Architecture in Twentieth-Century Epistolary Fiction
\end{center}

Epistolary framing devices invite readers to reconstruct historical meaning from fragmentary personal records rather than from an omniscient narrator. By foregrounding the materiality of letters, diaries, and marginal annotations, twentieth-century novelists transform transmission gaps into central sites of interpretive tension.

\section*{Archival Fragments and Unreliable Witnessing}
When correspondence is interrupted or selectively preserved, silence becomes structurally expressive. Readers must weigh competing chronologies and infer motives across unstated intervals, mirroring the work of archival scholarship itself.

\end{document}
"""#
        ),
        LaTeXTemplate(
            id: "stem-lab-report",
            name: "STEM Lab Report",
            subtitle: "Physics, Chemistry, & Engineering laboratory report with siunitx units, mhchem formulas, and error analysis",
            icon: "flask",
            category: "STEM & Theses",
            content: #"""
\documentclass[11pt,letterpaper]{article}
\usepackage[margin=0.9in]{geometry}
\usepackage{amsmath,amssymb}
\usepackage{booktabs}
\usepackage{graphicx}
\usepackage{siunitx}
\usepackage[version=4]{mhchem}
\usepackage{pgfplots}
\pgfplotsset{compat=1.18}
\usepackage{hyperref}

\title{\textbf{Laboratory Report: Determination of Gravitational Acceleration via Simple Pendulum}}
\author{Lab Partner A \and Lab Partner B \\ Course: PHYS 101L — Experimental Mechanics}
\date{\today}

\begin{document}
\maketitle

\begin{abstract}
We measure the oscillation period $T$ of a simple pendulum across five string lengths $L \in [\qty{0.20}{m}, \qty{1.00}{m}]$ to determine local gravitational acceleration $g$. Linear regression of $T^2$ versus $L$ yields $g = \qty{9.79(8)}{m/s^2}$, consistent with the accepted value within experimental uncertainty.
\end{abstract}

\section{Objective \& Theory}
For small angular displacements ($\theta_0 < \qty{10}{\degree}$), the period $T$ obeys:
\begin{equation}\label{eq:pendulum}
  T = 2\pi \sqrt{\frac{L}{g}} \quad \Longrightarrow \quad T^2 = \frac{4\pi^2}{g} L.
\end{equation}
In complementary titration calibration checks, aqueous neutralization followed $\ce{HCl + NaOH -> NaCl + H2O}$.

\section{Experimental Data}
\begin{table}[htbp]
  \centering
  \caption{Measured Pendulum Length and Mean Oscillation Period ($N = 10$ Trials)}
  \label{tab:lab-data}
  \begin{tabular}{@{}SSS@{}}
    \toprule
    {\textbf{Length $L$ (\unit{m})}} & {\textbf{Period $T$ (\unit{s})}} & {\textbf{$T^2$ (\unit{s^2})}} \\
    \midrule
    0.20 & 0.90 & 0.81 \\
    0.40 & 1.27 & 1.61 \\
    0.60 & 1.56 & 2.43 \\
    0.80 & 1.80 & 3.24 \\
    1.00 & 2.01 & 4.04 \\
    \bottomrule
  \end{tabular}
\end{table}

\section{Error Analysis \& Conclusion}
Propagating timing uncertainty $\delta T = \qty{0.02}{s}$ and length uncertainty $\delta L = \qty{0.002}{m}$ yields a relative error below \qty{1.0}{\%}.

\end{document}
"""#
        ),
        LaTeXTemplate(
            id: "university-thesis",
            name: "University Thesis / Dissertation",
            subtitle: "Multi-chapter book-class thesis with table of contents, list of figures/tables, and theorem support",
            icon: "books.vertical",
            category: "STEM & Theses",
            content: #"""
\documentclass[12pt,letterpaper,oneside]{book}
\usepackage[margin=1.25in]{geometry}
\usepackage{setspace}
\usepackage{amsmath,amssymb,amsthm}
\usepackage{booktabs}
\usepackage{graphicx}
\usepackage[style=authoryear,backend=bibtex]{biblatex}
\usepackage{csquotes}
\usepackage{hyperref}

\onehalfspacing
\newtheorem{theorem}{Theorem}[chapter]
\newtheorem{definition}{Definition}[chapter]

\title{\textbf{Scalable Symbolic-Numeric Methods for Structured Scientific Modeling}}
\author{Doctoral Candidate Name \\ Department of Applied Mathematics \\ University Graduate School}
\date{\today}

\begin{document}

\frontmatter
\maketitle

\chapter*{Abstract}
This dissertation investigates hybrid symbolic-numeric algorithms that preserve algebraic invariants during long-horizon physical simulations.

\tableofcontents
\listoffigures
\listoftables

\mainmatter

\chapter{Introduction}
\section{Motivation and Scope}
Long-horizon numerical integration often suffers from secular energy drift when discrete schemes ignore underlying geometric structure.

\section{Dissertation Outline}
Chapter 2 establishes theoretical stability guarantees; Chapter 3 evaluates benchmark accuracy across stiff oscillatory systems.

\chapter{Theoretical Foundations}
\begin{definition}[Symplectic Step]
A one-step integrator $\Phi_h$ is symplectic if its Jacobian preserves the canonical two-form $\omega = \mathrm{d}p \wedge \mathrm{d}q$.
\end{definition}

\end{document}
"""#
        ),
        LaTeXTemplate(
            id: "beamer-slides",
            name: "Academic Beamer Presentation",
            subtitle: "16:9 conference & thesis defense slide deck with Madrid/metropolis structure, blocks, and equations",
            icon: "play.rectangle",
            category: "STEM & Theses",
            content: #"""
\documentclass[aspectratio=169]{beamer}
\usetheme{Madrid}
\usecolortheme{default}

\usepackage{amsmath,amssymb}
\usepackage{booktabs}

\title[Thesis Defense]{Deterministic Authoring Pipelines for Scholarly Publishing}
\author{Presenter Name}
\institute{Department of Computer Science}
\date{\today}

\begin{document}

\begin{frame}
  \titlepage
\end{frame}

\begin{frame}{Outline}
  \tableofcontents
\end{frame}

\section{Motivation}
\begin{frame}{Why Authoring Ergonomics Matter}
  \begin{itemize}
    \item Graduate students spend hours debugging cryptic TeX error logs.
    \item Broken relative asset paths cause last-minute submission failures.
    \item Instant pre-flight feedback eliminates avoidable formatting penalties.
  \end{itemize}
\end{frame}

\section{Core Results}
\begin{frame}{Key Formulation}
  \begin{block}{Objective Function}
    Minimize editing friction while preserving full \LaTeX{} transparency:
    \[
      \mathcal{L} = \tau_{\text{compile}} + \lambda \, \text{Errors}_{\text{unresolved}}.
    \]
  \end{block}
\end{frame}

\begin{frame}{Summary}
  \begin{itemize}
    \item Real-time prose spellchecking + bibliography style switching.
    \item Clean self-contained \texttt{.zip} submission packaging.
  \end{itemize}
\end{frame}

\end{document}
"""#
        )
    ]

    public static let snippets: [LaTeXSnippet] = [
        LaTeXSnippet(
            id: "expl3-block",
            title: "ExplSyntaxOn ... ExplSyntaxOff Block",
            category: "LaTeX3 (expl3)",
            description: "Enables the LaTeX3 programming syntax regime where spaces are ignored and _ and : are letters.",
            code: """
\\ExplSyntaxOn

% Define variables and functions here
\\tl_new:N \\l_my_module_text_tl

\\ExplSyntaxOff
"""
        ),
        LaTeXSnippet(
            id: "xparse-cmd",
            title: "\\NewDocumentCommand (xparse)",
            category: "LaTeX3 (xparse)",
            description: "Define a modern document command with optional (O{default}), starred (s), and mandatory (m) arguments.",
            code: """
\\NewDocumentCommand{\\mycommand}{ s O{default} m }
  {
    \\IfBooleanTF{#1}
      { \\textbf{#3} ~ (#2) }
      { \\emph{#3} ~ [#2] }
  }
"""
        ),
        LaTeXSnippet(
            id: "xparse-env",
            title: "\\NewDocumentEnvironment (xparse)",
            category: "LaTeX3 (xparse)",
            description: "Define a modern environment with full access to #1, #2 in both begin and end blocks.",
            code: """
\\NewDocumentEnvironment{mybox}{ O{Title} m }
  {
    \\par\\medskip\\noindent\\textbf{#1 (#2)}\\par\\noindent\\ignorespaces
  }
  {
    \\par\\medskip
  }
"""
        ),
        LaTeXSnippet(
            id: "l3keys-def",
            title: "\\keys_define:nn (l3keys)",
            category: "LaTeX3 (expl3)",
            description: "Define a key-value option family with typed variables and defaults.",
            code: """
\\ExplSyntaxOn
\\tl_new:N \\l_my_title_tl
\\bool_new:N \\l_my_draft_bool

\\keys_define:nn { mymodule }
  {
    title .tl_set:N   = \\l_my_title_tl,
    title .initial:n  = { Default~Title },
    draft .bool_set:N = \\l_my_draft_bool,
    draft .initial:n  = false,
  }
\\ExplSyntaxOff
"""
        ),
        LaTeXSnippet(
            id: "l3seq-map",
            title: "Sequence Mapping (\\seq_map_inline:Nn)",
            category: "LaTeX3 (expl3)",
            description: "Populate a sequence from a comma-separated list and iterate over items.",
            code: """
\\ExplSyntaxOn
\\seq_new:N \\l_my_items_seq
\\NewDocumentCommand{\\RenderItems}{ m }
  {
    \\seq_set_from_clist:Nn \\l_my_items_seq { #1 }
    \\begin{itemize}
      \\seq_map_inline:Nn \\l_my_items_seq { \\item ##1 }
    \\end{itemize}
  }
\\ExplSyntaxOff
"""
        ),
        LaTeXSnippet(
            id: "l3fp-eval",
            title: "Floating-Point Evaluation (\\fp_eval:n)",
            category: "LaTeX3 (expl3)",
            description: "Evaluate IEEE 754 floating-point math directly in LaTeX3.",
            code: "\\ExplSyntaxOn\n\\fp_eval:n { round(sin(pi / 4) * sqrt(2), 6) }\n\\ExplSyntaxOff"
        ),
        LaTeXSnippet(
            id: "booktabs-table",
            title: "Publication Table (booktabs)",
            category: "Tables & Figures",
            description: "Clean publication-grade table using \\toprule, \\midrule, and \\bottomrule.",
            code: """
\\begin{table}[htbp]
  \\centering
  \\begin{tabular}{@{}lcr@{}}
    \\toprule
    Parameter & Symbol & Value \\\\
    \\midrule
    Learning rate & $\\eta$ & $10^{-3}$ \\\\
    Batch size & $B$ & $64$ \\\\
    \\bottomrule
  \\end{tabular}
  \\caption{Experimental hyperparameters.}
  \\label{tab:params}
\\end{table}
"""
        ),
        LaTeXSnippet(
            id: "aligned-math",
            title: "Multi-line Aligned Equations",
            category: "Mathematics",
            description: "AMS align environment for multi-step derivations.",
            code: """
\\begin{align}
  \\mathcal{L}(\\theta) &= \\mathbb{E}_{x \\sim p}[\\log q_\\theta(x)] \\\\
                       &\\le \\int p(x) \\log q_\\theta(x)\\,\\mathrm{d}x.
\\end{align}
"""
        ),
        LaTeXSnippet(
            id: "python-listings",
            title: "Python Source Code Block (listings)",
            category: "Python & Code",
            description: "Syntax-highlighted Python code listing with frame and line numbers.",
            code: """
\\begin{lstlisting}[language=Python, caption={Python implementation}, numbers=left, frame=single, basicstyle=\\ttfamily\\small]
def gradient_step(x: list[float], lr: float = 1e-2) -> list[float]:
    return [xi - lr * (2.0 * xi) for xi in x]
\\end{lstlisting}
"""
        ),
        LaTeXSnippet(
            id: "algorithm2e-block",
            title: "Pythonic Pseudocode (algorithm2e)",
            category: "Python & Code",
            description: "Structured algorithm block with input/output and loop constructs.",
            code: """
\\begin{algorithm}[H]
  \\SetAlgoLined
  \\KwIn{Dataset $\\mathcal{D}$, step size $\\eta > 0$}
  \\KwOut{Optimized parameters $\\theta^\\star$}
  Initialize $\\theta_0 \\gets 0$\\;
  \\For{$t = 1, 2, \\dots, T$}{
    $\\theta_t \\gets \\theta_{t-1} - \\eta \\nabla \\mathcal{L}(\\theta_{t-1}; \\mathcal{D})$\\;
  }
  \\Return $\\theta_T$
  \\caption{Stochastic Gradient Descent}
\\end{algorithm}
"""
        )
    ]

    public static let commonPackages: [LaTeXPackagePreset] = [
        LaTeXPackagePreset(id: "expl3", package: "expl3", options: "", category: "LaTeX3 Core", description: "LaTeX3 programming layer (l3kernel): token lists, integers, sequences, floating-point, and keys."),
        LaTeXPackagePreset(id: "xparse", package: "xparse", options: "", category: "LaTeX3 Core", description: "High-level document command and environment declarations (\\NewDocumentCommand)."),
        LaTeXPackagePreset(id: "l3keys2e", package: "l3keys2e", options: "", category: "LaTeX3 Core", description: "Process package and class options using l3keys."),
        LaTeXPackagePreset(id: "amsmath", package: "amsmath", options: "", category: "Mathematics", description: "AMS mathematical facilities (align, gather, matrices, operators)."),
        LaTeXPackagePreset(id: "amssymb", package: "amssymb", options: "", category: "Mathematics", description: "Extended AMS mathematical symbol collection (\\mathbb, \\mathfrak)."),
        LaTeXPackagePreset(id: "mathtools", package: "mathtools", options: "", category: "Mathematics", description: "Enhancements to amsmath including paired delimiters and cramped styles."),
        LaTeXPackagePreset(id: "amsthm", package: "amsthm", options: "", category: "Mathematics", description: "Theorem, lemma, definition, and proof environments."),
        LaTeXPackagePreset(id: "siunitx", package: "siunitx", options: "", category: "Mathematics", description: "LaTeX3-powered SI units and numerical column formatting (\\qty, \\num)."),
        LaTeXPackagePreset(id: "geometry", package: "geometry", options: "margin=1in", category: "Layout & Typography", description: "Flexible page layout and margin configuration."),
        LaTeXPackagePreset(id: "fontspec", package: "fontspec", options: "", category: "Layout & Typography", description: "XeTeX/LuaTeX OpenType and TrueType font selection (\\setmainfont, \\setsansfont, \\setmonofont)."),
        LaTeXPackagePreset(id: "libertinus", package: "libertinus", options: "", category: "Layout & Typography", description: "Libertinus serif, sans-serif, and math font family for XeTeX/LaTeX."),
        LaTeXPackagePreset(id: "ebgaramond", package: "ebgaramond", options: "", category: "Layout & Typography", description: "Classic EB Garamond serif typography."),
        LaTeXPackagePreset(id: "fira", package: "fira", options: "sfdefault", category: "Layout & Typography", description: "Mozilla Fira Sans and Fira Mono font suite."),
        LaTeXPackagePreset(id: "plex", package: "plex", options: "", category: "Layout & Typography", description: "IBM Plex Serif, Sans, and Mono font family."),
        LaTeXPackagePreset(id: "lmodern", package: "lmodern", options: "", category: "Layout & Typography", description: "Latin Modern scalable serif, sans, mono, and math fonts."),
        LaTeXPackagePreset(id: "tgpagella", package: "tgpagella", options: "", category: "Layout & Typography", description: "TeX Gyre Pagella (Palatino-inspired) book serif typeface."),
        LaTeXPackagePreset(id: "microtype", package: "microtype", options: "", category: "Layout & Typography", description: "Subliminal micro-typographic refinements and character protrusion."),
        LaTeXPackagePreset(id: "booktabs", package: "booktabs", options: "", category: "Layout & Typography", description: "Publication-quality tables (\\toprule, \\midrule, \\bottomrule)."),
        LaTeXPackagePreset(id: "enumitem", package: "enumitem", options: "", category: "Layout & Typography", description: "Customizable list environments (itemize, enumerate, description)."),
        LaTeXPackagePreset(id: "xcolor", package: "xcolor", options: "dvipsnames", category: "Graphics & Color", description: "Driver-independent color extensions and tinting."),
        LaTeXPackagePreset(id: "graphicx", package: "graphicx", options: "", category: "Graphics & Color", description: "Enhanced support for including graphics and PDF figures."),
        LaTeXPackagePreset(id: "tikz", package: "tikz", options: "", category: "Graphics & Color", description: "PGF/TikZ programmatic vector graphics and diagrams."),
        LaTeXPackagePreset(id: "hyperref", package: "hyperref", options: "colorlinks=true", category: "Links & References", description: "Cross-referencing hyperlinks, PDF bookmarks, and metadata."),
        LaTeXPackagePreset(id: "cleveref", package: "cleveref", options: "capitalize", category: "Links & References", description: "Intelligent cross-referencing (\\cref automatically formats Fig., Eq., Sec.)."),
        LaTeXPackagePreset(id: "pythonhighlight", package: "pythonhighlight", options: "", category: "Python & Code", description: "Zero-setup Python syntax highlighting (\\begin{python} ... \\end{python}, \\pyth{...}, \\inputpython)."),
        LaTeXPackagePreset(id: "pythontex", package: "pythontex", options: "", category: "Python & Code", description: "Execute and typeset Python code, SymPy symbolic math, and plots inside LaTeX (\\py, \\pyc, pycode)."),
        LaTeXPackagePreset(id: "minted", package: "minted", options: "frozencache", category: "Python & Code", description: "Pygments-based syntax highlighting for Python and 300+ languages (\\begin{minted}{python})."),
        LaTeXPackagePreset(id: "pyluatex", package: "pyluatex", options: "", category: "Python & Code", description: "Embed and evaluate Python sessions directly inside LaTeX documents."),
        LaTeXPackagePreset(id: "listings", package: "listings", options: "", category: "Python & Code", description: "Pure-TeX source code printer supporting language=Python without external shell-escape."),
        LaTeXPackagePreset(id: "algorithm2e", package: "algorithm2e", options: "ruled,vlined,linesnumbered", category: "Python & Code", description: "Publication-grade algorithmic pseudocode blocks (\\KwIn, \\KwOut, \\For, \\While)."),
        LaTeXPackagePreset(id: "biblatex", package: "biblatex", options: "style=authoryear,backend=bibtex", category: "Academic Writing", description: "Modern configurable bibliography engine supporting APA-compatible author-year, IEEE, MLA, Chicago, and Nature styles."),
        LaTeXPackagePreset(id: "natbib", package: "natbib", options: "", category: "Academic Writing", description: "Flexible author-year and numerical citations (\\citep, \\citet)."),
        LaTeXPackagePreset(id: "pgfplots", package: "pgfplots", options: "", category: "Graphics & Color", description: "Publication-grade data plots, bar charts, and scatter plots directly inside TikZ."),
        LaTeXPackagePreset(id: "subcaption", package: "subcaption", options: "", category: "Graphics & Color", description: "Side-by-side subfigures and subtables with individual subcaptions (\\begin{subfigure})."),
        LaTeXPackagePreset(id: "setspace", package: "setspace", options: "", category: "Academic Writing", description: "Clean single, 1.5x, and double line spacing (\\doublespacing, \\onehalfspacing)."),
        LaTeXPackagePreset(id: "lineno", package: "lineno", options: "", category: "Academic Writing", description: "Margin line numbers for anonymous peer review and manuscript submissions (\\linenumbers)."),
        LaTeXPackagePreset(id: "apa7", package: "apa7", options: "stu", category: "Academic Writing", description: "Official APA 7th edition student and manuscript document formatting."),
        LaTeXPackagePreset(id: "IEEEtran", package: "IEEEtran", options: "", category: "Academic Writing", description: "IEEE Transactions and conference paper styling macros."),
        LaTeXPackagePreset(id: "acmart", package: "acmart", options: "", category: "Academic Writing", description: "Association for Computing Machinery conference and journal formatting."),
        LaTeXPackagePreset(id: "mhchem", package: "mhchem", options: "version=4", category: "Mathematics", description: "Typeset chemical formulas and reaction equations effortlessly (\\ce{H2O}, \\ce{A -> B}).")
    ]

    public static let ctanFontPresets: [CTANFontPreset] = [
        CTANFontPreset(
            id: "libertinus",
            name: "Libertinus (Serif + Math)",
            packageName: "libertinus",
            options: "",
            classification: "Math + Serif",
            description: "Modern Linux Libertine fork with matched OpenType math and sans-serif fonts."
        ),
        CTANFontPreset(
            id: "ebgaramond",
            name: "EB Garamond",
            packageName: "ebgaramond",
            options: "",
            classification: "Serif",
            description: "Classical 16th-century Garamond revival designed for long-form books and articles."
        ),
        CTANFontPreset(
            id: "fira",
            name: "Fira Sans & Mono",
            packageName: "fira",
            options: "sfdefault",
            classification: "Sans-Serif",
            description: "Clean geometric humanist sans-serif and code monospace font family."
        ),
        CTANFontPreset(
            id: "plex",
            name: "IBM Plex",
            packageName: "plex",
            options: "",
            classification: "Sans-Serif",
            description: "Coordinated IBM Plex Serif, Sans, and Mono families for technical documentation."
        ),
        CTANFontPreset(
            id: "lmodern",
            name: "Latin Modern",
            packageName: "lmodern",
            options: "",
            classification: "Math + Serif",
            description: "High-resolution scalable successor to Computer Modern with full math support."
        ),
        CTANFontPreset(
            id: "tgpagella",
            name: "TeX Gyre Pagella",
            packageName: "tgpagella",
            options: "",
            classification: "Serif",
            description: "Palatino-inspired academic book serif with crisp small caps and old-style figures."
        )
    ]

    /// Builds a customized academic starter document from `PaperSetupConfig` with sanitized TeX metadata.
    public static func generateWizardDocument(from config: PaperSetupConfig) -> String {
        let baseTemplate = templates.first(where: { $0.id == config.templateId })
            ?? templates.first(where: { $0.id == "apa7-student" })
            ?? defaultTemplate

        var source = baseTemplate.content
        let pt = min(max(config.baseFontSizePt, 10), 12)
        let paperOpt = config.paperSize.rawValue

        // 1. Update documentclass paper size & font size if standard article/book class options exist
        if let docRegex = try? NSRegularExpression(pattern: #"^\\documentclass(?:\[([^\]]*)\])?\{([^}]+)\}"#, options: [.anchorsMatchLines]),
           let match = docRegex.firstMatch(in: source, range: NSRange(location: 0, length: (source as NSString).length)) {
            let ns = source as NSString
            let existingOpts = match.range(at: 1).location != NSNotFound ? ns.substring(with: match.range(at: 1)) : ""
            let docClass = ns.substring(with: match.range(at: 2))
            if docClass == "article" || docClass == "book" || docClass == "report" {
                var opts = existingOpts
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.hasSuffix("pt") && $0 != "letterpaper" && $0 != "a4paper" && !$0.isEmpty }
                opts.insert("\(pt)pt", at: 0)
                opts.insert(paperOpt, at: 1)
                let newDecl = "\\documentclass[\(opts.joined(separator: ","))]{\(docClass)}"
                if let swiftRange = Range(match.range, in: source) {
                    source.replaceSubrange(swiftRange, with: newDecl)
                }
            }
        }

        // 2. Sanitize and apply Title / Author / Institution / Course
        let cleanTitle = AcademicSanitizer.escapeLaTeXText(config.title, allowSafeInlineMath: true)
        let safeTitle = cleanTitle.isEmpty ? "Untitled Academic Paper" : cleanTitle

        let safeAuthor: String
        if config.anonymizedBlindReview {
            safeAuthor = "Anonymous Author(s) \\\\ Anonymous Institution"
        } else {
            let authorName = AcademicSanitizer.escapeLaTeXText(config.author)
            let institution = AcademicSanitizer.escapeLaTeXText(config.institution)
            let course = AcademicSanitizer.escapeLaTeXText(config.courseOrVenue)
            let parts = [
                authorName.isEmpty ? "Student Author" : authorName,
                institution,
                course
            ].filter { !$0.isEmpty }
            safeAuthor = parts.joined(separator: " \\\\ ")
        }

        source = replaceTopLevelCommandArg(in: source, command: "title", newArg: "\\textbf{\(safeTitle)}")
        source = replaceTopLevelCommandArg(in: source, command: "author", newArg: safeAuthor)

        // 3. Bibliography style preset
        let bibOption = config.bibliographyStyle.biblatexStyleOption
        if let bibRegex = try? NSRegularExpression(pattern: #"\\usepackage(?:\[[^\]]*\])?\{biblatex\}"#) {
            let ns = source as NSString
            let replacement = "\\usepackage[style=\(bibOption),backend=bibtex]{biblatex}"
            if bibRegex.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)) != nil {
                source = bibRegex.stringByReplacingMatches(
                    in: source,
                    range: NSRange(location: 0, length: ns.length),
                    withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
                )
            } else if let beginDocRange = source.range(of: "\\begin{document}") {
                source.insert(contentsOf: "\\usepackage[style=\(bibOption),backend=bibtex]{biblatex}\n\\addbibresource{references.bib}\n", at: beginDocRange.lowerBound)
            }
        }

        // 4. Double spacing
        if config.doubleSpacing {
            if !source.contains("\\usepackage{setspace}") {
                if let beginDocRange = source.range(of: "\\begin{document}") {
                    source.insert(contentsOf: "\\usepackage{setspace}\n", at: beginDocRange.lowerBound)
                }
            }
            source = source.replacingOccurrences(of: "\\onehalfspacing", with: "\\doublespacing")
            source = source.replacingOccurrences(of: "\\singlespacing", with: "\\doublespacing")
            if !source.contains("\\doublespacing"), let beginDocRange = source.range(of: "\\begin{document}") {
                source.insert(contentsOf: "\\doublespacing\n", at: beginDocRange.lowerBound)
            }
        } else {
            source = source.replacingOccurrences(of: "\\doublespacing\n", with: "")
            source = source.replacingOccurrences(of: "\\doublespacing", with: "")
        }

        // 5. Blind review line numbers
        if config.anonymizedBlindReview {
            source = SubmissionExportService.applyBlindReviewTransform(to: source)
        }

        return source
    }

    private static func replaceTopLevelCommandArg(in source: String, command: String, newArg: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\\\\(command)\\s*\\{") else {
            return source
        }
        let ns = source as NSString
        guard let match = regex.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)),
              let startIdx = Range(match.range, in: source)?.upperBound else {
            return source
        }
        var depth = 1
        var cursor = startIdx
        while cursor < source.endIndex && depth > 0 {
            let ch = source[cursor]
            if ch == "\\" {
                let next = source.index(after: cursor)
                if next < source.endIndex {
                    cursor = source.index(after: next)
                    continue
                }
            } else if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    break
                }
            }
            cursor = source.index(after: cursor)
        }
        guard depth == 0 else { return source }
        var updated = source
        updated.replaceSubrange(startIdx..<cursor, with: newArg)
        return updated
    }
}
