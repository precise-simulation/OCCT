#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <STEPControl_Reader.hxx>
#include <STEPControl_StepModelType.hxx>
#include <STEPControl_Writer.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS_Shape.hxx>
#include <gp_Pnt.hxx>

#include <cstdio>

int main()
{
  const TopoDS_Shape aBox1 = BRepPrimAPI_MakeBox(10.0, 20.0, 30.0).Shape();
  const TopoDS_Shape aBox2 = BRepPrimAPI_MakeBox(gp_Pnt(5.0, 0.0, 0.0), 10.0, 20.0, 30.0).Shape();
  const TopoDS_Shape aFused = BRepAlgoAPI_Fuse(aBox1, aBox2).Shape();
  if (aFused.IsNull() || !BRepCheck_Analyzer(aFused).IsValid())
  {
    return 10;
  }

  const char* aStepPath = "occt-sdk-consumer.step";
  STEPControl_Writer aWriter;
  if (aWriter.Transfer(aFused, STEPControl_AsIs) != IFSelect_RetDone
   || aWriter.Write(aStepPath) != IFSelect_RetDone)
  {
    return 20;
  }

  STEPControl_Reader aReader;
  if (aReader.ReadFile(aStepPath) != IFSelect_RetDone
   || aReader.TransferRoots() <= 0)
  {
    return 30;
  }

  const TopoDS_Shape aRoundTrip = aReader.OneShape();
  std::remove(aStepPath);
  if (aRoundTrip.IsNull() || !BRepCheck_Analyzer(aRoundTrip).IsValid())
  {
    return 40;
  }

  bool hasValidSolid = aRoundTrip.ShapeType() == TopAbs_SOLID;
  for (TopExp_Explorer anExplorer(aRoundTrip, TopAbs_SOLID); anExplorer.More(); anExplorer.Next())
  {
    if (BRepCheck_Analyzer(anExplorer.Current()).IsValid())
    {
      hasValidSolid = true;
      break;
    }
  }
  if (!hasValidSolid)
  {
    return 50;
  }

  return 0;
}
