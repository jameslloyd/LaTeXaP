import Foundation

public struct LaTeXTemplate: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let icon: String
    public let content: String
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
        LaTeXPackagePreset(id: "algorithm2e", package: "algorithm2e", options: "ruled,vlined,linesnumbered", category: "Python & Code", description: "Publication-grade algorithmic pseudocode blocks (\\KwIn, \\KwOut, \\For, \\While).")
    ]
}
