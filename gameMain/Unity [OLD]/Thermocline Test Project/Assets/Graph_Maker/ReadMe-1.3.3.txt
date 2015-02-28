----------------------------------------------
            Graph Maker
 Copyright © 2014 Stuart S.
    http://forum.unity3d.com/threads/202437
----------------------------------------------

Thank you for buying Graph Maker!

Please read the manual (GraphMaker.pdf) for detailed documentation on how to use this package.

For questions, suggestions, bugs: email rorakin3@gmail.com or post in the Unity thread.

-----------------
 Installation
-----------------

This pack supports 5 platforms:

Daikon Forge (Graph_Maker_DF)
NGUI + Unity 4 (Graph_Maker_NGUI_Unity_4)
NGUI + Unity 3.5 (Graph_Maker_NGUI_Unity_3.5)
NGUI 2.7 + Unity 4 (Graph_Maker_NGUI_2.7_Unity_4)
NGUI 2.7 + Unity 3.5 (Graph_Maker_NGUI_2.7_Unity_3.5)

Can only install one at a time.

Note that HOTween is by default included in the package for animations. 
If HOTween is already in your project, make sure to uncheck the HOTween folder during import.

The following features are not supported in all platforms:

Not yet supported in Daikon - see http://www.daikonforge.com/dfgui/forums/topic/issue-creating-pie-chart/
-Pie Graph

Not supported and no plans to support for any package other than NGUI + Unity 4 (Time consuming to create and mostly unused features)
-Editor scene
-World Map example scene
-Skill Tree example scene

Not supported and no plans to support in NGUI + Unity 3.5, NGUI 2.7 + Unity 4, NGUI 2.7 + Unity 3.5 (Time consuming to create)
-Data generation example scene

-----------------
 Version History
-----------------

1.3.3
- NEW: Click and hover events have been added to make adding interactivity to graphs is very easy.
- NEW: Line padding variable added to series script to allow creating lines that don't exactly touch at the point. Useful for creating hollow points.
- NEW: Hide x / y axis tick boolean variables added to the graph, can be used to show / hide axis ticks independently of labels and vice versa.
- NEW: Hide legend labels boolan variable added, useful now that legend events can be added, since this can be shown in a tooltip.
- NEW: API for dynamically instantiating and deleting series, useful if you don't know how many series you will have for a given graph.
- NEW: NGUI 2.7 is now supported for both Unity 4 and Unity 3.5.
- CHANGE: Data generation example scene code is now mostly GUI system independent.
- CHANGE: Functionality in the manager script has been split up: caching, data generators, events, and path finding are now smaller separate scripts.

1.3.2
- NEW: Animations! Example scene has been updated to demonstrate the use of the animation functions. All animations use HOTween.
- FIX: Fixed issues for Daikon version upgrade 1.0.13 -> 1.0.14
- FIX: Different default link prefab is now used for all lines in all graphs, which improves overall line quality.
- FIX: Axis Graph script is now fully cached, performance should be the best it can possibly be. This removed the refresh every frame variable.
- NOTE: These changes break backwards compatibility, but can be easily addressed
- FIX: Prefab reference variables moved from series to graph script, so they don't need to be set for each series.
- FIX: Line Width variable renamed to Line Scale

1.3.1
- FIX: Fixed issue discovered when upgrading DFGUI version where first label not positioned correctly
- FIX: WMG_Grid now implements caching, increasing general performance for all graphs (WMG_Grid is used for grid lines and axis labels)

1.3
- NOTE: This version brings many changes that break backwards compatibility, highly recommend remaking your existing graphs from the new examples.
- NEW: New interactive example scene added for both NGUI and Daikon that showcases many Graph Maker features.
- NEW: Ability to do real-time update for an arbitrary float variable (uses reflection similar to property binding in Daikon).
- NEW: Codebase refactored to use nearly all GUI independent code. All NGUI and Daikon specific code in a manager script.
- NEW: Ability to automatically set x / y axis min / max values based on series point data added.
- NEW: Ability to specify an axes type. This sets the axes positions based on a quadrant type.
- NEW: Added an axes width variable to more easily change the width of the axes.
- NEW: Legend entry font size variable added.
- NEW: Connect first to last variable added, which links the first and last points. Useful for creating a circle.
- NEW: Added hide x / y labels variables.
- FIX: Huge performance improvement for the update every frame functionality with caching, this removed the series update boolean.
- FIX: Resolved offset issues in Daikon due to differences in pivot / position behavior in NGUI vs Daikon.
- FIX: Auto space based on number of points variables moved from graph script to series script.
- FIX: Replaced point / line prefab variables with a list of prefabs to easily switch prefabs at runtime.
- FIX: "Don't draw ... by default" and list of booleans "Hide Lines / Points" replaced with single hide points / lines boolean.
- FIX: Changed the axis lines to always be center pivoted to resolve some axis positioning issues.
- FIX: Fixed some vertical vs horizontal issues. Behavior is to swap many x / y specific values instead of rotate everything.
- FIX: Tick offset float variables replaced with above vs below and right vs left booleans. The axes type automatically sets these.

1.2.1:
- NEW: Added support for Daikon Forge
- NEW: Added support for NGUI + Unity 3.5

1.2:
- NEW: Upgraded from NGUI 2.7 to 3.0
- NEW: Graph type parameter to switch between line, side-by-side bar, stacked bar, and percentage stacked bar.
- NEW: Orientation type parameter to switch between vertical and horizontal graphs. Useful for horizontal bar charts.
- NEW: Added parameters to control placement of axes and what axis arrows display. Can now make 4-quadrant graphs.
- NEW: Scatter plot prefab added to showcase changes made to better support scatter plots.
- FIX: Series point value data changed from Float to Vector2 to more easily support scatter plots and arbitrary data plotting.
- FIX: Negative values did not update all labels properly, and data was also not positioned correctly for negative values.

1.1:
- NEW: First Unity Asset Store published version

1.0:
- NEW: Created
